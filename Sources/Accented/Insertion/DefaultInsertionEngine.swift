import AppKit
import os

/// Context + commit for the picker. Strategies are those the #2 spike measured;
/// this type does not invent a second path.
///
/// ## Paths
///   - `insert-unicode` — browse commit: `keyboardSetUnicodeString` → session tap
///   - `replace-backspace` — variants commit: delete then that insert
///   - `copy-pasteboard` — Accessibility off (#5 degraded). The picker shows the toast.
///
/// Not shipped (spike cut them): AX `kAXSelectedText` replace (Safari lies), pasteboard
/// save/⌘V/restore as a CGEvent fallback, `postToPid`, settle delay after `orderOut`.
///
/// ## Per-app quirks
///   - Chromium / Electron (Chrome, VS Code, Slack): insert/replace work once a text
///     field is focused; caret bounds are 0×0 → mouse. Bare `AXWebArea` / `AXButton`
///     is a miss — fail open to browse.
///   - Terminal: `AXValue` is the whole scrollback; preceding char comes from
///     `kAXStringForRange`. Bounds 0×0.
///   - Notes: `AXTable` means the sidebar — fail open. Body `AXTextArea` is normal.
///   - Word: focused `AXSplitGroup` has no range; insert still lands. Always browse + mouse.
///
/// Call `commit` only after the panel has `orderOut`'d (spike: 0 ms is enough).
@MainActor
final class DefaultInsertionEngine: InsertionEngine {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Insertion")
    private let catalog: () -> CharacterCatalog
    private let isDegraded: () -> Bool
    private let defaults: UserDefaults

    /// Roles that are not a text caret even if AX returns an element.
    private static let opaqueRoles: Set<String> = [
        "AXTable", "AXOutline", "AXSplitGroup", "AXButton",
    ]

    init(
        catalog: @escaping () -> CharacterCatalog,
        isDegraded: @escaping () -> Bool,
        defaults: UserDefaults = .standard
    ) {
        self.catalog = catalog
        self.isDegraded = isDegraded
        self.defaults = defaults
    }

    func currentContext() -> PickerContext {
        if isDegraded() {
            logger.info("Context path=degraded mode=browse caret=nil")
            return PickerContext(mode: .browse, caretRect: nil)
        }
        guard let snap = AXCaretReader.snapshot() else {
            logger.info("Context path=no-focused-element mode=browse caret=nil")
            return PickerContext(mode: .browse, caretRect: nil)
        }
        if let role = snap.focusedRole, Self.opaqueRoles.contains(role) {
            logger.info("Context path=opaque-role role=\(role, privacy: .public) mode=browse caret=nil")
            return PickerContext(mode: .browse, caretRect: nil)
        }
        let preceding = snap.preceding?.first
        let mode = InsertionContextDecision.mode(
            preceding: preceding,
            selectedLength: snap.selectedLength,
            catalog: catalog()
        )
        logger.info("Context path=ax role=\(snap.focusedRole ?? "nil", privacy: .public) mode=\(String(describing: mode), privacy: .public) caret=\(snap.cocoaBounds != nil, privacy: .public)")
        return PickerContext(mode: mode, caretRect: snap.cocoaBounds)
    }

    func commit(_ variant: AccentVariant, for context: PickerContext) {
        let uppercase: Bool
        switch context.mode {
        case .variants(_, let upper): uppercase = upper
        case .browse: uppercase = false
        }
        let glyph = variant.glyph(uppercase: uppercase)

        if isDegraded() {
            logger.info("Commit path=copy-pasteboard glyph=\(glyph, privacy: .public)")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(glyph, forType: .string)
            UsageCounts.bump(variant.character, in: defaults)
            return
        }

        switch context.mode {
        case .variants:
            logger.info("Commit path=replace-backspace glyph=\(glyph, privacy: .public)")
            EventPoster.postBackspace()
            EventPoster.postUnicode(glyph)
        case .browse:
            logger.info("Commit path=insert-unicode glyph=\(glyph, privacy: .public)")
            EventPoster.postUnicode(glyph)
        }
        UsageCounts.bump(variant.character, in: defaults)
    }
}
