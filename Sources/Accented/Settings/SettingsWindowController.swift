import AppKit
import SwiftUI
import os

/// Standalone Settings window. SwiftUI `TabView` hosted in AppKit, reused across opens
/// (`isReleasedWhenClosed = false`). Same instance of `SettingsStore` / `PermissionsManager`
/// the rest of the app observes.
@MainActor
final class SettingsWindowController: NSWindowController {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Settings")
    private let store: SettingsStore

    init(store: SettingsStore, permissions: PermissionsManager, checkForUpdates: @escaping () -> Void) {
        self.store = store
        let hosting = NSHostingController(
            rootView: SettingsView(
                store: store,
                permissions: permissions,
                checkForUpdates: checkForUpdates
            )
        )
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.windowSize.width,
                                height: SettingsView.windowSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Accented Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support NSCoder")
    }

    override func showWindow(_ sender: Any?) {
        logger.info("Showing Settings window")
        store.refreshLaunchAtLoginFromSystem()
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissions: PermissionsManager
    let checkForUpdates: () -> Void

    static let windowSize = CGSize(width: 500, height: 620)

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store, permissions: permissions, checkForUpdates: checkForUpdates)
                .tabItem { Label("General", systemImage: "gearshape") }
            LanguagesSettingsTab(store: store)
                .tabItem { Label("Languages", systemImage: "globe") }
            CharactersSettingsTab(store: store)
                .tabItem { Label("Characters", systemImage: "textformat.abc") }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissions: PermissionsManager
    let checkForUpdates: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ProcessInfo.processInfo.processName)
                            .font(.title2.weight(.semibold))
                        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                            Text("Version \(version)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }

            Section {
                HotkeyRecorderView(hotkey: $store.hotkey)
                Picker("Also trigger with", selection: $store.doubleTapModifier) {
                    ForEach(DoubleTapModifier.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Double-press ⌘ is on by default, and the ⌥Space combo works alongside it. Double-press is two quick taps. ⌘C and a held ⌘ do not open the picker. Double-press needs Accessibility.")
            }

            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
            } header: {
                Text("General")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                        Text("Required to see the text cursor and type characters. Without it, Accented still opens and copies the selection.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    statusBadge(permissions.accessibility)
                }
                if !permissions.accessibility.isGranted {
                    HStack {
                        Button("Grant Access") { _ = permissions.requestAccessibility() }
                        Button("Open System Settings…") { permissions.openAccessibilitySettings() }
                    }
                }
            } header: {
                Text("Permissions")
            }

            Section {
                Toggle("Automatically check for updates", isOn: $store.automaticallyChecksForUpdates)
                HStack {
                    Button("Check for Updates…") { checkForUpdates() }
                    Spacer()
                }
            } header: {
                Text("Software Update")
            } footer: {
                Text("Accented checks for new versions and verifies each download before installing.")
            }

            Section {
                Text("Feedback: [github.com/thatjuan/accented](https://github.com/thatjuan/accented/issues)")
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Feedback")
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refreshLaunchAtLoginFromSystem() }
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
        let granted = status.isGranted
        Label(granted ? "Granted" : "Not granted",
              systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundColor(granted ? .green : .orange)
            .labelStyle(.titleAndIcon)
    }
}

// MARK: - Languages

private struct LanguagesSettingsTab: View {
    @ObservedObject var store: SettingsStore
    /// Non-nil while the editor sheet is up. Holds the draft's identity, not a store reference.
    @State private var editing: CustomPalette?

    var body: some View {
        Form {
            Section {
                ForEach(LanguagePresets.all, id: \.id) { preset in
                    Toggle(isOn: binding(for: preset.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text(preset.sample)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("The picker shows the union of every enabled language.")
            }

            Section {
                ForEach(store.customPalettes) { palette in
                    HStack {
                        Toggle(isOn: binding(for: palette.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(palette.name)
                                Text(LanguagePresets.preset(for: palette).sample)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("Edit…") { editing = palette }
                    }
                }
                Button("New palette…") {
                    editing = CustomPalette(id: CustomPalette.newID(), name: "", glyphs: [])
                }
            } header: {
                Text("Custom palettes")
            } footer: {
                if store.customPalettes.isEmpty {
                    Text("Build a palette with only the characters you want. Enable it on its own or together with a language.")
                }
            }

            Section {
                Picker("Order", selection: $store.orderingMode) {
                    ForEach(OrderingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } header: {
                Text("Ordering")
            } footer: {
                Text("\"Most used\" puts characters you pick more often first. Counts update as you type.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { palette in
            PaletteEditorView(
                palette: palette,
                isNew: !store.customPalettes.contains { $0.id == palette.id },
                onSave: { store.savePalette($0) },
                onDelete: { store.deletePalette(id: palette.id) }
            )
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { store.enabledPresetIDs.contains(id) },
            set: { enabled in
                if enabled {
                    if !store.enabledPresetIDs.contains(id) {
                        store.enabledPresetIDs.append(id)
                    }
                } else {
                    store.enabledPresetIDs.removeAll { $0 == id }
                    if store.enabledPresetIDs.isEmpty {
                        store.enabledPresetIDs = ["es"]
                    }
                }
            }
        )
    }
}

// MARK: - Characters

private struct CharactersSettingsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var search = ""
    @State private var showingAdd = false
    @State private var addText = ""
    @State private var addBase: String = "e"

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search characters…", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(filteredGroups, id: \.id) { group in
                        Section {
                            ForEach(group.variants, id: \.character) { variant in
                                characterCell(variant)
                            }
                        } header: {
                            HStack {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Button("Add custom…") { showingAdd = true }
                    .popover(isPresented: $showingAdd, arrowEdge: .top) {
                        addCustomPopover
                    }
                Spacer()
                Button("Reset to defaults", role: .destructive) {
                    store.resetCharactersToDefaults()
                }
            }
        }
        .padding(16)
    }

    private struct DisplayGroup: Identifiable {
        let id: String
        let title: String
        let variants: [AccentVariant]
    }

    private var filteredGroups: [DisplayGroup] {
        let catalog = CharacterCatalog(
            configuration: CatalogConfiguration(
                enabledPresetIDs: store.enabledPresetIDs,
                disabledCharacters: [],
                customVariants: store.catalogConfiguration().customVariants,
                customExtras: store.customExtras,
                orderingMode: .presetOrder
            )
        )
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalog.allGroups().compactMap { group in
            let variants = group.variants.filter { variant in
                query.isEmpty
                    || variant.character.lowercased().contains(query)
                    || variant.uppercase.lowercased().contains(query)
            }
            guard !variants.isEmpty else { return nil }
            let title = group.base.map { String($0).uppercased() } ?? "Extras"
            let id = group.base.map { String($0) } ?? "extras"
            return DisplayGroup(id: id, title: title, variants: variants)
        }
    }

    private func characterCell(_ variant: AccentVariant) -> some View {
        let on = !store.isDisabled(variant.character)
        return GlyphCell(
            glyph: variant.character,
            isOn: on,
            help: on ? "Click to disable \(variant.character)" : "Click to enable \(variant.character)"
        ) {
            store.toggleDisabled(variant.character)
        }
    }

    private var addCustomPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add custom characters").font(.headline)
            TextField("Characters", text: $addText)
                .textFieldStyle(.roundedBorder)
            Picker("Attach to", selection: $addBase) {
                ForEach(baseOptions, id: \.self) { option in
                    Text(option == "extras" ? "Extras" : option.uppercased()).tag(option)
                }
            }
            HStack {
                Spacer()
                Button("Add") {
                    let glyphs = addText.map { String($0) }.filter { $0 != " " }
                    if addBase == "extras" {
                        store.addCustom(glyphs: glyphs, base: nil)
                    } else if let base = addBase.first {
                        store.addCustom(glyphs: glyphs, base: base)
                    }
                    addText = ""
                    showingAdd = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(addText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private var baseOptions: [String] {
        var options = LanguagePresets.nativeHoldKeyOrder.map { String($0.base) }
        options.append("extras")
        return options
    }
}
