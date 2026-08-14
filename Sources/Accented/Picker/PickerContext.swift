import Foundation

/// Snapshot the picker needs from the insertion engine (#7).
///
/// `caretRect` is Cocoa bottom-left coordinates (already flipped from AX). `nil` means
/// "put the panel near the mouse" — degraded mode, or AX could not see a caret.
struct PickerContext: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        /// Preceding character matched an enabled base letter. Commit **replaces** it.
        case variants(base: Character, uppercase: Bool)
        /// No matching base. Commit **inserts**. Browse can filter down to a letter group
        /// (still insert, not replace).
        case browse
    }

    var mode: Mode
    var caretRect: CGRect?
}

/// #7 surface. #6 develops against this; `StubInsertionEngine` stands in until the real
/// engine lands. Commit is called **after** the panel has `orderOut`'d (spike: events
/// follow key focus, 0 ms after resign is enough).
@MainActor
protocol InsertionEngine: AnyObject {
    func currentContext() -> PickerContext
    func commit(_ variant: AccentVariant, for context: PickerContext)
}
