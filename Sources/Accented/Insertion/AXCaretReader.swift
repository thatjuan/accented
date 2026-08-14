import AppKit
import ApplicationServices

/// Thin AX adapter: focused element → preceding char, caret rect (Cocoa), role.
///
/// Quirks (from `docs/spikes/insertion-fidelity.md`):
///   - Prefer `kAXStringForRangeParameterizedAttribute` over the whole `AXValue`
///     (Terminal's value is the entire scrollback).
///   - 0×0 bounds (Chrome, VS Code, Terminal) are treated as missing → mouse fallback.
///   - `AXTable` / `AXSplitGroup` / `AXButton` are not text carets; caller fail-opens.
enum AXCaretReader {

    struct Snapshot {
        var preceding: String?
        var selectedLength: Int
        var cocoaBounds: CGRect?
        var focusedRole: String?
    }

    static func snapshot() -> Snapshot? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focused = copy(systemWide, kAXFocusedUIElementAttribute as String) else { return nil }
        let element = focused as! AXUIElement

        var snap = Snapshot(preceding: nil, selectedLength: 0, cocoaBounds: nil, focusedRole: nil)
        snap.focusedRole = copy(element, kAXRoleAttribute as String) as? String

        guard let range = copyRange(element, kAXSelectedTextRangeAttribute as String) else {
            return snap
        }
        snap.selectedLength = range.length

        if range.length == 0, range.location > 0 {
            var one = CFRange(location: range.location - 1, length: 1)
            if let axRange = AXValueCreate(.cfRange, &one) {
                snap.preceding = copyParameterizedString(
                    element, kAXStringForRangeParameterizedAttribute as String, axRange
                )
            }
        }

        let caret = CFRange(location: range.location, length: 0)
        snap.cocoaBounds = usableBounds(element, range: caret)
        if snap.cocoaBounds == nil {
            let one = CFRange(location: max(range.location - 1, 0), length: 1)
            snap.cocoaBounds = usableBounds(element, range: one)
        }
        return snap
    }

    /// Cocoa bottom-left, or `nil` when AX hands back an empty/zero rect.
    private static func usableBounds(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var mutable = range
        guard let axRange = AXValueCreate(.cfRange, &mutable) else { return nil }
        guard let raw = copyParameterized(element, kAXBoundsForRangeParameterizedAttribute as String, axRange),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var ax = CGRect.zero
        guard AXValueGetValue(raw as! AXValue, .cgRect, &ax) else { return nil }
        if ax.isNull || ax.isInfinite || (ax.width == 0 && ax.height == 0) { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? ax.maxY
        return CGRect(x: ax.origin.x, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func copyRange(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func copyParameterized(_ element: AXUIElement, _ attribute: String, _ parameter: AXValue) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        return err == .success ? value : nil
    }

    private static func copyParameterizedString(_ element: AXUIElement, _ attribute: String, _ parameter: AXValue) -> String? {
        copyParameterized(element, attribute, parameter) as? String
    }
}
