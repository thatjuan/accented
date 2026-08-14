import AppKit
import Carbon.HIToolbox

/// A single key + modifier combo. Persisted as `settings.hotkeyKeyCode` /
/// `settings.hotkeyModifiers` so `SettingsStore` (#8) can take over without a key rename.
///
/// `keyCode` is a Carbon virtual key (`kVK_*`). `modifiers` are AppKit device-independent flags.
struct Hotkey: Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    /// ⌥Space — unused by default macOS, mnemonic ("option" = options for this letter).
    static let `default` = Hotkey(keyCode: UInt32(kVK_Space), modifiers: .option)

    /// Slots the manager can register. v1 uses only `picker`; the list shape keeps a second
    /// binding (e.g. browse-vs-context) cheap later without building it now.
    enum Slot: String, CaseIterable, Sendable {
        case picker
        var carbonID: UInt32 {
            switch self {
            case .picker: return 1
            }
        }
    }

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// `⌥␣`-style label for the recorder and Settings.
    var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += Self.glyph(forKeyCode: keyCode)
        return parts
    }

    enum Denial: Equatable, Sendable {
        /// A letter/digit with only Shift (or nothing) — would steal typing.
        case needsModifier
        /// Reserved system / app combo.
        case reserved(String)
    }

    /// Deny-list: bare letters/digits, ⌘Q, ⌘W, ⌘Space.
    func denial() -> Denial? {
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        let nonShift = mods.subtracting(.shift)

        if Self.isLetterOrDigit(keyCode), nonShift.isEmpty {
            return .needsModifier
        }
        if mods == .command, keyCode == UInt32(kVK_ANSI_Q) {
            return .reserved("⌘Q")
        }
        if mods == .command, keyCode == UInt32(kVK_ANSI_W) {
            return .reserved("⌘W")
        }
        if mods == .command, keyCode == UInt32(kVK_Space) {
            return .reserved("⌘Space")
        }
        return nil
    }

    static func from(event: NSEvent) -> Hotkey {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: flags)
    }

    static func glyph(forKeyCode keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "␣"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return glyphFromLayout(keyCode) ?? "•"
        }
    }

    private static func isLetterOrDigit(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
             kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
             kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
             kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
             kVK_ANSI_Y, kVK_ANSI_Z,
             kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
             kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9:
            return true
        default:
            return false
        }
    }

    /// Current keyboard layout, uppercase. Falls back to a small US table.
    private static func glyphFromLayout(_ keyCode: UInt32) -> String? {
        let input = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData) else {
            return usLetter(keyCode)
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return usLetter(keyCode)
            }
            var deadKeyState: UInt32 = 0
            var chars: [UniChar] = [0, 0, 0, 0]
            var length: Int = 0
            let err = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard err == noErr, length > 0 else { return usLetter(keyCode) }
            let string = String(utf16CodeUnits: chars, count: length)
            return string.uppercased()
        }
    }

    private static func usLetter(_ keyCode: UInt32) -> String? {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
        ]
        return map[keyCode]
    }
}

// MARK: - Persistence (UserDefaults until SettingsStore #8)

enum HotkeyDefaults {
    static let keyCodeKey = "settings.hotkeyKeyCode"
    static let modifiersKey = "settings.hotkeyModifiers"

    static func load(from defaults: UserDefaults = .standard) -> Hotkey {
        let storedCode = defaults.object(forKey: keyCodeKey) as? Int
        let storedMods = defaults.object(forKey: modifiersKey) as? UInt
        guard let storedCode, let storedMods else { return .default }
        return Hotkey(
            keyCode: UInt32(storedCode),
            modifiers: NSEvent.ModifierFlags(rawValue: storedMods)
                .intersection([.command, .option, .control, .shift])
        )
    }

    static func save(_ hotkey: Hotkey, to defaults: UserDefaults = .standard) {
        defaults.set(Int(hotkey.keyCode), forKey: keyCodeKey)
        defaults.set(hotkey.modifiers.rawValue, forKey: modifiersKey)
    }
}
