import AppKit
import SwiftUI

/// Stub Settings host for #4 — just the hotkey recorder. Replaced by the real
/// `SettingsWindowController` in #8. Same window rules #8 will use: titled, non-resizable,
/// `isReleasedWhenClosed = false`, reused across opens.
@MainActor
final class HotkeySettingsWindowController: NSWindowController {

    private var store: HotkeyStubStore

    init(store: HotkeyStubStore) {
        self.store = store
        let root = HotkeyStubSettingsView(store: store)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Accented Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 140))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// Tiny observable stand-in until `SettingsStore` (#8) owns the hotkey.
@MainActor
final class HotkeyStubStore: ObservableObject {
    @Published var hotkey: Hotkey {
        didSet {
            guard hotkey != oldValue else { return }
            HotkeyDefaults.save(hotkey)
            onChange?(hotkey)
        }
    }

    var onChange: ((Hotkey) -> Void)?

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }
}

private struct HotkeyStubSettingsView: View {
    @ObservedObject var store: HotkeyStubStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global hotkey")
                .font(.headline)
            Text("Press the combo to show the picker, from any app.")
                .foregroundStyle(.secondary)
            HotkeyRecorderView(hotkey: $store.hotkey)
        }
        .padding(20)
        .frame(minWidth: 380, alignment: .leading)
    }
}
