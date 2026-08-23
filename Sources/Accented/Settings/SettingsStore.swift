import AppKit
import Combine
import Foundation
import ServiceManagement
import os

/// Single source of truth for user-configurable settings. Port of the diarc `SettingsStore`
/// recipe: injected `UserDefaults`, namespaced `settings.*` keys, `@Published` + persisting
/// `didSet`, `init` loads without triggering writes.
///
/// ## How to add a setting
/// 1. Namespace the key under `enum Key`.
/// 2. Declare a `@Published` property with a `didSet` that writes to `defaults`.
///    `didSet` does not fire for the assignment in `init`.
/// 3. Load the value in `init`, falling back to the behavior-preserving default.
///    Default-ON bools use `object(forKey:) == nil` (not `bool(forKey:)`, which is false when absent).
@MainActor
final class SettingsStore: ObservableObject {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Settings")

    private enum Key {
        static let enabledPresetIDs = "settings.enabledPresetIDs"
        static let disabledCharacters = "settings.disabledCharacters"
        static let customVariants = "settings.customVariants"
        static let customExtras = "settings.customExtras"
        static let customPalettes = "settings.customPalettes"
        static let orderingMode = "settings.orderingMode"
        static let usageCounts = "settings.usageCounts"
        static let hotkeyKeyCode = "settings.hotkeyKeyCode"
        static let hotkeyModifiers = "settings.hotkeyModifiers"
        static let doubleTapModifier = "settings.doubleTapModifier"
        static let launchAtLogin = "settings.launchAtLogin"
    }

    private let defaults: UserDefaults

    @Published var enabledPresetIDs: [String] = ["es"] {
        didSet { defaults.set(enabledPresetIDs, forKey: Key.enabledPresetIDs) }
    }

    @Published var disabledCharacters: [String] = [] {
        didSet { defaults.set(disabledCharacters, forKey: Key.disabledCharacters) }
    }

    /// Base letter (as a one-character string) → extra glyphs.
    @Published var customVariants: [String: [String]] = [:] {
        didSet { defaults.set(try? JSONEncoder().encode(customVariants), forKey: Key.customVariants) }
    }

    @Published var customExtras: [String] = [] {
        didSet { defaults.set(customExtras, forKey: Key.customExtras) }
    }

    /// User-built palettes (#25). Enabled/disabled through `enabledPresetIDs` like a language.
    @Published var customPalettes: [CustomPalette] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(customPalettes), forKey: Key.customPalettes) }
    }

    @Published var orderingMode: OrderingMode = .presetOrder {
        didSet { defaults.set(orderingMode.rawValue, forKey: Key.orderingMode) }
    }

    /// MRU tallies. Not `@Published` — bookkeeping, not a Settings control.
    var usageCounts: [String: Int] = [:] {
        didSet { defaults.set(try? JSONEncoder().encode(usageCounts), forKey: Key.usageCounts) }
    }

    @Published var hotkey: Hotkey = .default {
        didSet {
            defaults.set(Int(hotkey.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(hotkey.modifiers.rawValue, forKey: Key.hotkeyModifiers)
        }
    }

    /// Extra trigger: two quick taps of ⌘ or ⌥. Default off so existing users keep ⌥Space only.
    @Published var doubleTapModifier: DoubleTapModifier = .off {
        didSet { defaults.set(doubleTapModifier.rawValue, forKey: Key.doubleTapModifier) }
    }

    /// Launch at Login preference. The system (`SMAppService`) is source of truth when
    /// available; this property is the binding surface and a persisted last-known value.
    @Published var launchAtLogin: Bool = false {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// Sparkle-owned. No `Key`, no `didSet`, not loaded in `init`. #9 seeds this from the
    /// updater and writes changes back. Binding surface only.
    @Published var automaticallyChecksForUpdates: Bool = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedPresets = defaults.stringArray(forKey: Key.enabledPresetIDs) ?? ["es"]
        self.enabledPresetIDs = storedPresets.isEmpty ? ["es"] : storedPresets
        self.disabledCharacters = defaults.stringArray(forKey: Key.disabledCharacters) ?? []
        self.customVariants = (defaults.data(forKey: Key.customVariants))
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        self.customExtras = defaults.stringArray(forKey: Key.customExtras) ?? []
        self.customPalettes = (defaults.data(forKey: Key.customPalettes))
            .flatMap { try? JSONDecoder().decode([CustomPalette].self, from: $0) } ?? []
        if let raw = defaults.string(forKey: Key.orderingMode) {
            if raw == "mostRecentlyUsed" {
                self.orderingMode = .mostUsed
            } else {
                self.orderingMode = OrderingMode(rawValue: raw) ?? .presetOrder
            }
        } else {
            self.orderingMode = .presetOrder
        }
        self.usageCounts = (defaults.data(forKey: Key.usageCounts))
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]

        if defaults.object(forKey: Key.hotkeyKeyCode) != nil,
           defaults.object(forKey: Key.hotkeyModifiers) != nil {
            self.hotkey = HotkeyDefaults.load(from: defaults)
        } else {
            self.hotkey = .default
        }
        if let raw = defaults.string(forKey: Key.doubleTapModifier),
           let mode = DoubleTapModifier(rawValue: raw) {
            self.doubleTapModifier = mode
        } else {
            self.doubleTapModifier = .off
        }
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)

        logger.info("SettingsStore initialized (presets: \(self.enabledPresetIDs.joined(separator: ","), privacy: .public))")
    }

    /// Catalog snapshot for the picker / engine. Rebuild on each hotkey; cheap.
    func catalogConfiguration() -> CatalogConfiguration {
        var byBase: [Character: [String]] = [:]
        for (key, glyphs) in customVariants {
            guard let base = key.first else { continue }
            byBase[base, default: []].append(contentsOf: glyphs)
        }
        return CatalogConfiguration(
            enabledPresetIDs: enabledPresetIDs,
            disabledCharacters: disabledCharacters,
            customVariants: byBase,
            customExtras: customExtras,
            orderingMode: orderingMode,
            customPalettes: customPalettes
        )
    }

    func makeCatalog() -> CharacterCatalog {
        CharacterCatalog(configuration: catalogConfiguration(), usageCounts: usageCounts)
    }

    func bumpUsage(_ glyph: String) {
        let key = glyph.lowercased()
        guard !key.isEmpty else { return }
        usageCounts[key, default: 0] += 1
    }

    func toggleDisabled(_ glyph: String) {
        let key = glyph.lowercased()
        if let index = disabledCharacters.firstIndex(where: { $0.lowercased() == key }) {
            disabledCharacters.remove(at: index)
        } else {
            disabledCharacters.append(key)
        }
    }

    func isDisabled(_ glyph: String) -> Bool {
        disabledCharacters.contains { $0.lowercased() == glyph.lowercased() }
    }

    func addCustom(glyphs: [String], base: Character?) {
        let cleaned = glyphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        if let base {
            let key = String(base).lowercased()
            var existing = customVariants[key] ?? []
            for glyph in cleaned where !existing.contains(glyph) {
                existing.append(glyph)
            }
            customVariants[key] = existing
        } else {
            for glyph in cleaned where !customExtras.contains(glyph) {
                customExtras.append(glyph)
            }
        }
    }

    /// Upsert by id. A brand-new palette is enabled straight away — nobody builds one to leave it off.
    func savePalette(_ palette: CustomPalette) {
        if let index = customPalettes.firstIndex(where: { $0.id == palette.id }) {
            customPalettes[index] = palette
        } else {
            customPalettes.append(palette)
            if !enabledPresetIDs.contains(palette.id) {
                enabledPresetIDs.append(palette.id)
            }
        }
    }

    /// Remove the palette and its enabled entry, falling back to Spanish if nothing is left on.
    func deletePalette(id: String) {
        customPalettes.removeAll { $0.id == id }
        enabledPresetIDs.removeAll { $0 == id }
        if enabledPresetIDs.isEmpty {
            enabledPresetIDs = ["es"]
        }
    }

    /// Characters-tab reset only. Palettes live on the Languages tab and survive it.
    func resetCharactersToDefaults() {
        disabledCharacters = []
        customVariants = [:]
        customExtras = []
    }

    /// Read Launch at Login from `SMAppService` (user can flip it in System Settings).
    func refreshLaunchAtLoginFromSystem() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at Login change failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshLaunchAtLoginFromSystem()
    }
}
