import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Stand-in for issue #7. Enough AX + session-tap posting for the picker to be usable
/// in TextEdit and friends; #7 replaces this with the real engine (usage counts,
/// pasteboard-restore edge cases, tests).
///
/// Strategies from `docs/spikes/insertion-fidelity.md`:
///   - context: system-wide focused element, selected range, preceding char, bounds
///   - fail open to browse + `caretRect = nil`
///   - insert: `keyboardSetUnicodeString` → `.cgSessionEventTap`
///   - replace: backspace then that insert
///   - degraded: pasteboard copy (toast is the picker's job)
@MainActor
final class StubInsertionEngine: InsertionEngine {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Insertion")
    private let catalog: () -> CharacterCatalog
    private let isDegraded: () -> Bool

    init(catalog: @escaping () -> CharacterCatalog, isDegraded: @escaping () -> Bool) {
        self.catalog = catalog
        self.isDegraded = isDegraded
    }

    func currentContext() -> PickerContext {
        if isDegraded() {
            logger.info("Context: degraded — browse, no caret")
            return PickerContext(mode: .browse, caretRect: nil)
        }
        guard let snap = snapshot() else {
            return PickerContext(mode: .browse, caretRect: nil)
        }
        var mode: PickerContext.Mode = .browse
        if let preceding = snap.preceding, let base = preceding.first,
           !catalog().variants(forBase: base).isEmpty {
            mode = .variants(base: base, uppercase: base.isUppercase)
        }
        let caret = snap.cocoaBounds.flatMap { rect -> CGRect? in
            (rect.isNull || rect.isInfinite || (rect.width == 0 && rect.height == 0)) ? nil : rect
        }
        logger.info("Context mode=\(String(describing: mode), privacy: .public) caret=\(caret != nil, privacy: .public)")
        return PickerContext(mode: mode, caretRect: caret)
    }

    func commit(_ variant: AccentVariant, for context: PickerContext) {
        let uppercase: Bool
        switch context.mode {
        case .variants(_, let upper):
            uppercase = upper
        case .browse:
            uppercase = false
        }
        let glyph = variant.glyph(uppercase: uppercase)
        logger.info("Commit \"\(glyph, privacy: .public)\" replace=\(String(describing: context.mode), privacy: .public)")

        if isDegraded() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(glyph, forType: .string)
            logger.notice("Degraded commit — copied \"\(glyph, privacy: .public)\" to pasteboard")
            return
        }

        switch context.mode {
        case .variants:
            postKey(UInt32(kVK_Delete))
            postUnicode(glyph)
        case .browse:
            postUnicode(glyph)
        }
    }

    // MARK: - AX

    private struct Snap {
        var preceding: String?
        var cocoaBounds: CGRect?
    }

    private func snapshot() -> Snap? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        var range = CFRange()
        var haveRange = false
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            haveRange = AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)
        }

        var snap = Snap()
        if haveRange, range.location > 0 {
            var one = CFRange(location: range.location - 1, length: 1)
            if let axRange = AXValueCreate(.cfRange, &one) {
                var strRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &strRef
                ) == .success {
                    snap.preceding = strRef as? String
                }
            }
            if snap.preceding == nil {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String {
                    let idx = value.index(value.startIndex, offsetBy: min(range.location - 1, max(value.count - 1, 0)))
                    if idx < value.endIndex { snap.preceding = String(value[idx]) }
                }
            }
        }

        if haveRange {
            let caret = CFRange(location: range.location, length: 0)
            snap.cocoaBounds = bounds(element, range: caret)
            if snap.cocoaBounds == nil || snap.cocoaBounds == .zero {
                let one = CFRange(location: max(range.location - 1, 0), length: 1)
                snap.cocoaBounds = bounds(element, range: one)
            }
        }
        return snap
    }

    private func bounds(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var mutable = range
        guard let axRange = AXValueCreate(.cfRange, &mutable) else { return nil }
        var rectRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &rectRef
        ) == .success, let rectRef, CFGetTypeID(rectRef) == AXValueGetTypeID() else { return nil }
        var ax = CGRect.zero
        guard AXValueGetValue(rectRef as! AXValue, .cgRect, &ax) else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? ax.maxY
        return CGRect(x: ax.origin.x, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height)
    }

    // MARK: - CGEvent

    private func postUnicode(_ string: String) {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        let utf16 = Array(string.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cgSessionEventTap)
        usleep(12_000)
        up.post(tap: .cgSessionEventTap)
    }

    private func postKey(_ keyCode: UInt32) {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
        else { return }
        down.post(tap: .cgSessionEventTap)
        usleep(12_000)
        up.post(tap: .cgSessionEventTap)
    }
}
