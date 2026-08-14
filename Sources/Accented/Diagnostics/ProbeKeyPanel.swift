import AppKit

/// Tiny `.nonactivatingPanel` used by the issue-#2 focus measurement.
///
/// Mirrors the picker contract issue #6 will ship: `.nonactivatingPanel` + `canBecomeKey = true`.
/// A text field is the sink we watch — if session-tap unicode lands here, events followed key
/// focus to the panel; if it lands in the target app, they still reach the previously focused
/// field.
final class ProbeKeyPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    let sink = NSTextField(string: "")

    init() {
        super.init(
            contentRect: NSRect(x: 80, y: 80, width: 280, height: 72),
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        backgroundColor = NSColor.black.withAlphaComponent(0.85)
        hasShadow = true

        let label = NSTextField(labelWithString: "PROBE (key panel)")
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.frame = NSRect(x: 12, y: 44, width: 256, height: 16)

        sink.frame = NSRect(x: 12, y: 12, width: 256, height: 24)
        sink.placeholderString = "events land here if the panel ate them"
        sink.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 72))
        content.addSubview(label)
        content.addSubview(sink)
        contentView = content
    }

    func resetSink() {
        sink.stringValue = ""
    }
}
