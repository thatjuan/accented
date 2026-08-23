@testable import Accented
import AppKit
import Foundation

#if canImport(Testing)
import Testing

@Suite
@MainActor
struct SettingsStoreTests {

    private func suite(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "com.thatjuan.accented.settings-tests.\(name)")!
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.contains("settings.enabledPresetIDs")
            ? (defaults.volatileDomainNames.first ?? "")
            : "com.thatjuan.accented.settings-tests.\(name)")
        defaults.removePersistentDomain(forName: "com.thatjuan.accented.settings-tests.\(name)")
        return defaults
    }

    @Test
    func defaultsAreSpanishPresetOrder() {
        let store = SettingsStore(defaults: suite())
        #expect(store.enabledPresetIDs == ["es"])
        #expect(store.disabledCharacters.isEmpty)
        #expect(store.orderingMode == .presetOrder)
        #expect(store.hotkey == .default)
        #expect(store.doubleTapModifier == .command)
    }

    @Test
    func persistsAndReloadsEveryControl() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: "com.thatjuan.accented.settings-tests.\(name)")!
        defaults.removePersistentDomain(forName: "com.thatjuan.accented.settings-tests.\(name)")

        let writer = SettingsStore(defaults: defaults)
        writer.enabledPresetIDs = ["es", "fr"]
        writer.disabledCharacters = ["ä"]
        writer.customVariants = ["e": ["ə"]]
        writer.customExtras = ["†"]
        writer.customPalettes = [CustomPalette(id: "custom.persist", name: "Mine", glyphs: ["á", "ñ"])]
        writer.orderingMode = .mostUsed
        writer.hotkey = Hotkey(keyCode: 0, modifiers: [.command, .option])
        writer.doubleTapModifier = .command
        writer.launchAtLogin = true
        writer.bumpUsage("é")

        let reader = SettingsStore(defaults: defaults)
        #expect(reader.enabledPresetIDs == ["es", "fr"])
        #expect(reader.disabledCharacters == ["ä"])
        #expect(reader.customVariants["e"] == ["ə"])
        #expect(reader.customExtras == ["†"])
        #expect(reader.customPalettes == [CustomPalette(id: "custom.persist", name: "Mine", glyphs: ["á", "ñ"])])
        #expect(reader.orderingMode == .mostUsed)
        #expect(reader.hotkey.keyCode == 0)
        #expect(reader.hotkey.modifiers.contains(.command))
        #expect(reader.hotkey.modifiers.contains(.option))
        #expect(reader.doubleTapModifier == .command)
        #expect(reader.launchAtLogin)
        #expect(reader.usageCounts["é"] == 1)
    }

    @Test
    func enablingFrenchAddsOEToCatalog() {
        let store = SettingsStore(defaults: suite())
        store.enabledPresetIDs = ["es", "fr"]
        let glyphs = store.makeCatalog().variants(forBase: "o").map(\.character)
        #expect(glyphs.contains("œ"))
        #expect(glyphs.contains("ó"))
    }

    @Test
    func disablingCharacterRemovesItFromVariants() {
        let store = SettingsStore(defaults: suite())
        store.enabledPresetIDs = ["de"]
        store.toggleDisabled("ä")
        #expect(store.makeCatalog().variants(forBase: "a").isEmpty)
        store.toggleDisabled("ä")
        #expect(store.makeCatalog().variants(forBase: "a").map(\.character) == ["ä"])
    }

    @Test
    func customCharacterAppearsOnItsBase() {
        let store = SettingsStore(defaults: suite())
        store.addCustom(glyphs: ["ə"], base: "e")
        #expect(store.makeCatalog().variants(forBase: "e").map(\.character).contains("ə"))
    }

    @Test
    func emptyPresetListFallsBackToSpanish() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: "com.thatjuan.accented.settings-tests.\(name)")!
        defaults.removePersistentDomain(forName: "com.thatjuan.accented.settings-tests.\(name)")
        defaults.set([String](), forKey: "settings.enabledPresetIDs")
        let store = SettingsStore(defaults: defaults)
        #expect(store.enabledPresetIDs == ["es"])
    }

    @Test
    func automaticallyChecksForUpdatesIsNotPersisted() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: "com.thatjuan.accented.settings-tests.\(name)")!
        defaults.removePersistentDomain(forName: "com.thatjuan.accented.settings-tests.\(name)")
        let writer = SettingsStore(defaults: defaults)
        writer.automaticallyChecksForUpdates = false
        let reader = SettingsStore(defaults: defaults)
        #expect(reader.automaticallyChecksForUpdates == true)
    }

    // MARK: - Custom palettes (#25)

    @Test
    func savingNewPaletteEnablesItAndPersists() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: "com.thatjuan.accented.settings-tests.\(name)")!
        defaults.removePersistentDomain(forName: "com.thatjuan.accented.settings-tests.\(name)")

        let writer = SettingsStore(defaults: defaults)
        let palette = CustomPalette(id: CustomPalette.newID(), name: "Mine", glyphs: ["á", "í", "ñ"])
        writer.savePalette(palette)

        let reader = SettingsStore(defaults: defaults)
        #expect(reader.customPalettes == [palette])
        #expect(reader.enabledPresetIDs.contains(palette.id))
        #expect(reader.makeCatalog().variants(forBase: "n").map(\.character).contains("ñ"))
    }

    @Test
    func savingExistingPaletteUpdatesInPlace() {
        let store = SettingsStore(defaults: suite())
        var palette = CustomPalette(id: CustomPalette.newID(), name: "Mine", glyphs: ["á"])
        store.savePalette(palette)
        palette.glyphs = ["á", "ő"]
        store.savePalette(palette)
        #expect(store.customPalettes.count == 1)
        #expect(store.enabledPresetIDs.filter { $0 == palette.id }.count == 1)
        #expect(store.makeCatalog().variants(forBase: "o").map(\.character) == ["ő"])
    }

    @Test
    func deletingPaletteRemovesItFromEnabledAndFallsBack() {
        let store = SettingsStore(defaults: suite())
        let palette = CustomPalette(id: CustomPalette.newID(), name: "Mine", glyphs: ["á"])
        store.savePalette(palette)
        store.enabledPresetIDs = [palette.id]

        store.deletePalette(id: palette.id)
        #expect(store.customPalettes.isEmpty)
        #expect(store.enabledPresetIDs == ["es"])
    }

    @Test
    func resetCharactersKeepsPalettes() {
        let store = SettingsStore(defaults: suite())
        let palette = CustomPalette(id: CustomPalette.newID(), name: "Mine", glyphs: ["á"])
        store.savePalette(palette)
        store.resetCharactersToDefaults()
        #expect(store.customPalettes == [palette])
    }
}

#else

enum SettingsLinkCheck {
    static let defaultPresets = CatalogConfiguration.default.enabledPresetIDs
}

#endif
