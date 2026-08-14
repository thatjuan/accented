import CoreGraphics

/// Thin CGEvent adapter. Session tap + private state — not `postToPid` (Chromium
/// mangles pid-targeted events; see the #2 spike).
enum EventPoster {

    static let keyStrokeGapUs: useconds_t = 12_000

    static func postUnicode(_ string: String) {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        let utf16 = Array(string.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cgSessionEventTap)
        usleep(keyStrokeGapUs)
        up.post(tap: .cgSessionEventTap)
    }

    /// Backward delete (`kVK_Delete` / 0x33).
    static func postBackspace() {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
        else { return }
        down.post(tap: .cgSessionEventTap)
        usleep(keyStrokeGapUs)
        up.post(tap: .cgSessionEventTap)
    }
}
