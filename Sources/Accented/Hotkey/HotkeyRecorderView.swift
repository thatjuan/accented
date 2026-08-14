import AppKit
import SwiftUI

/// Settings control that records a key combo via a local `NSEvent` monitor while focused.
///
/// Renders `⌥␣`-style glyphs, rejects the deny-list with visible feedback, and offers
/// "Reset to default". Used by the #4 stub window and by Settings (#8).
struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey
    @State private var isRecording = false
    @State private var denialMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Hotkey")
                RecorderButton(
                    label: hotkey.displayString,
                    isRecording: $isRecording,
                    onCapture: { captured in
                        if let denial = captured.denial() {
                            denialMessage = Self.message(for: denial)
                            return
                        }
                        denialMessage = nil
                        isRecording = false
                        hotkey = captured
                    }
                )
                Button("Reset to default") {
                    denialMessage = nil
                    isRecording = false
                    hotkey = .default
                }
                .disabled(hotkey == .default)
            }
            if let denialMessage {
                Text(denialMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if isRecording {
                Text("Press a key combo. Esc cancels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func message(for denial: Hotkey.Denial) -> String {
        switch denial {
        case .needsModifier:
            return "Add ⌘, ⌥, or ⌃ — a bare letter would steal typing."
        case .reserved(let name):
            return "\(name) is reserved."
        }
    }
}

// MARK: - Focusable recorder button

private struct RecorderButton: NSViewRepresentable {
    var label: String
    @Binding var isRecording: Bool
    var onCapture: (Hotkey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, isRecording: $isRecording)
    }

    func makeNSView(context: Context) -> RecorderNSButton {
        let button = RecorderNSButton()
        button.coordinator = context.coordinator
        button.title = label
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ nsView: RecorderNSButton, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.isRecording = $isRecording
        nsView.title = isRecording ? "Type shortcut…" : label
        nsView.highlight(isRecording)
    }

    final class Coordinator {
        var onCapture: (Hotkey) -> Void
        var isRecording: Binding<Bool>

        init(onCapture: @escaping (Hotkey) -> Void, isRecording: Binding<Bool>) {
            self.onCapture = onCapture
            self.isRecording = isRecording
        }
    }
}

fileprivate final class RecorderNSButton: NSButton {
    var coordinator: RecorderButton.Coordinator?
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecording)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        tearDownMonitor()
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        coordinator?.isRecording.wrappedValue = true
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { installMonitor() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        tearDownMonitor()
        coordinator?.isRecording.wrappedValue = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        handle(event)
    }

    private func installMonitor() {
        tearDownMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func tearDownMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        coordinator?.onCapture(Hotkey.from(event: event))
    }
}

// Carbon constant without importing Carbon into the SwiftUI file's top level...
// kVK_Escape is 0x35; imported via the button file through Hotkey.swift's Carbon import
// is not re-exported. Use the numeric value.
private let kVK_Escape: Int = 0x35
