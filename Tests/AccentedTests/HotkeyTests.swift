@testable import Accented
import AppKit
import Carbon.HIToolbox

#if canImport(Testing)
import Testing

@Suite
struct HotkeyTests {

    @Test
    func defaultIsOptionSpace() {
        #expect(Hotkey.default.keyCode == UInt32(kVK_Space))
        #expect(Hotkey.default.modifiers == .option)
        #expect(Hotkey.default.displayString == "⌥␣")
    }

    @Test
    func denyBareLetter() {
        let hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: [])
        #expect(hotkey.denial() == .needsModifier)
        #expect(HotkeyRecorderView.message(for: .needsModifier).contains("bare letter"))
    }

    @Test
    func denyShiftOnlyLetter() {
        let hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: .shift)
        #expect(hotkey.denial() == .needsModifier)
    }

    @Test
    func denyCommandQAndWAndSpace() {
        #expect(Hotkey(keyCode: UInt32(kVK_ANSI_Q), modifiers: .command).denial() == .reserved("⌘Q"))
        #expect(Hotkey(keyCode: UInt32(kVK_ANSI_W), modifiers: .command).denial() == .reserved("⌘W"))
        #expect(Hotkey(keyCode: UInt32(kVK_Space), modifiers: .command).denial() == .reserved("⌘Space"))
    }

    @Test
    func allowOptionSpaceAndCommandOptionLetter() {
        #expect(Hotkey.default.denial() == nil)
        let combo = Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: [.command, .option])
        #expect(combo.denial() == nil)
        #expect(combo.displayString == "⌥⌘A")
    }

    @Test
    func carbonModifiersMatchCarbonFlags() {
        let hotkey = Hotkey(keyCode: UInt32(kVK_Space), modifiers: [.option, .shift])
        #expect(hotkey.carbonModifiers & UInt32(optionKey) != 0)
        #expect(hotkey.carbonModifiers & UInt32(shiftKey) != 0)
        #expect(hotkey.carbonModifiers & UInt32(cmdKey) == 0)
    }

    @Test
    func defaultsRoundTrip() {
        let suite = UserDefaults(suiteName: "com.thatjuan.accented.hotkey-tests")!
        suite.removePersistentDomain(forName: "com.thatjuan.accented.hotkey-tests")
        let original = Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: [.control, .option])
        HotkeyDefaults.save(original, to: suite)
        #expect(HotkeyDefaults.load(from: suite) == original)
        #expect(HotkeyDefaults.load(from: UserDefaults(suiteName: "com.thatjuan.accented.hotkey-tests-empty")!) == .default)
    }
}

#else

enum HotkeyLinkCheck {
    static let defaultCode = Hotkey.default.keyCode
}

#endif
