import SwiftUI

/// Sheet for building or editing a `CustomPalette` (#25).
///
/// Draft-only: the text field is the source of truth, the grid writes back into it, and
/// nothing reaches `SettingsStore` until Save. The live preview shows the exact rows the
/// picker will render for this palette, so nobody has to guess what they built.
struct PaletteEditorView: View {

    let isNew: Bool
    let onSave: (CustomPalette) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let paletteID: String
    @State private var name: String
    @State private var text: String
    /// A pristine draft should not be scolded for being empty; messages appear once edited.
    @State private var touchedName = false
    @State private var touchedText = false

    init(palette: CustomPalette, isNew: Bool, onSave: @escaping (CustomPalette) -> Void, onDelete: @escaping () -> Void) {
        self.paletteID = palette.id
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: palette.name)
        _text = State(initialValue: palette.glyphs.joined(separator: " "))
    }

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New palette" : "Edit palette")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Name")
                TextField("My palette", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _ in touchedName = true }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Characters")
                    .font(.subheadline.weight(.semibold))
                TextField("á í ñ", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .onChange(of: text) { _ in touchedText = true }
                ForEach(visibleProblems, id: \.self) { problem in
                    Text(problem)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Or pick from all diacritics")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Self.pickerSections) { section in
                            Section {
                                ForEach(section.glyphs, id: \.self) { glyph in
                                    GlyphCell(
                                        glyph: glyph,
                                        isOn: glyphs.contains(glyph),
                                        help: glyphs.contains(glyph)
                                            ? "Click to remove \(glyph)"
                                            : "Click to add \(glyph)"
                                    ) {
                                        toggle(glyph)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(section.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 170)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.subheadline.weight(.semibold))
                if previewRows.isEmpty {
                    Text("Nothing yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(previewRows) { row in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(row.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(row.glyphs)
                                        .font(.system(size: 15))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 74)
                }
            }

            Divider()

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(CustomPalette(id: paletteID, name: trimmedName, glyphs: glyphs))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!problems.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
    }

    // MARK: - Draft

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var glyphs: [String] {
        LanguagePresets.normalizeGlyphs(text)
    }

    /// Everything blocking Save, most specific first. Empty means the draft is savable.
    private var problems: [String] {
        var problems: [String] = []
        if text.contains("İ") {
            problems.append(Self.dottedCapitalIMessage)
        }
        if trimmedName.isEmpty {
            problems.append(Self.missingNameMessage)
        }
        if glyphs.isEmpty {
            problems.append(Self.missingGlyphsMessage)
        }
        return problems
    }

    /// The subset worth showing: an untouched field is empty because nothing has been typed
    /// yet, which the disabled Save button already says.
    private var visibleProblems: [String] {
        problems.filter { problem in
            switch problem {
            case Self.missingNameMessage: return touchedName
            case Self.missingGlyphsMessage: return touchedText
            default: return true
            }
        }
    }

    private static let dottedCapitalIMessage = "“İ” can’t be added on its own; add “ı” and it will pair with İ."
    private static let missingNameMessage = "Give the palette a name."
    private static let missingGlyphsMessage = "Add at least one character."

    private struct PreviewRow: Identifiable {
        let id: String
        let title: String
        let glyphs: String
    }

    /// The picker rows this palette alone produces — the same resolution the real picker runs.
    private var previewRows: [PreviewRow] {
        let draft = CustomPalette(id: paletteID, name: trimmedName, glyphs: glyphs)
        let catalog = CharacterCatalog(
            configuration: CatalogConfiguration(
                enabledPresetIDs: [draft.id],
                disabledCharacters: [],
                customVariants: [:],
                customExtras: [],
                orderingMode: .presetOrder,
                customPalettes: [draft]
            )
        )
        return catalog.allGroups().map { group in
            PreviewRow(
                id: group.base.map { String($0) } ?? "extras",
                title: group.base.map { String($0).uppercased() } ?? "Extras",
                glyphs: group.variants.map(\.character).joined(separator: "  ")
            )
        }
    }

    private func toggle(_ glyph: String) {
        var current = glyphs
        if let index = current.firstIndex(of: glyph) {
            current.remove(at: index)
        } else {
            current.append(glyph)
        }
        text = current.joined(separator: " ")
    }

    // MARK: - Pickable glyphs

    private struct PickerSection: Identifiable {
        let id: String
        let title: String
        let glyphs: [String]
    }

    /// Native hold-key glyphs plus every glyph a bundled preset adds on top (`ş`, `ı`, `ŀ`),
    /// extras last. Constant, so it is built once.
    private static let pickerSections: [PickerSection] = {
        var byBase: [Character: [String]] = [:]
        var order: [Character] = []
        for (base, glyphs) in LanguagePresets.nativeHoldKeyOrder {
            order.append(base)
            byBase[base] = glyphs
        }
        var extras: [String] = []

        for preset in LanguagePresets.all {
            for group in preset.groups {
                guard let base = group.base else { continue }
                if byBase[base] == nil {
                    order.append(base)
                    byBase[base] = []
                }
                for variant in group.variants where !byBase[base]!.contains(variant.character) {
                    byBase[base]!.append(variant.character)
                }
            }
            for extra in preset.extras where !extras.contains(extra.character) {
                extras.append(extra.character)
            }
        }

        var sections = order.map {
            PickerSection(id: String($0), title: String($0).uppercased(), glyphs: byBase[$0] ?? [])
        }
        if !extras.isEmpty {
            sections.append(PickerSection(id: "extras", title: "Extras", glyphs: extras))
        }
        return sections
    }()
}
