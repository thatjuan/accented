import AppKit

/// Floating accent popover. `.nonactivatingPanel` + `canBecomeKey = true` is the spike
/// contract: we get `keyDown` for navigation while the target app stays visually focused
/// (its field ring does not drop). Commit must `orderOut` before posting CGEvents or the
/// panel eats them.
@MainActor
final class PickerPanel: NSPanel {

    var onKeyDown: ((NSEvent) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 48),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Above ordinary windows of the frontmost app. `.floating` is easy to lose
        // behind a key window; the picker is a popover, not a document.
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
