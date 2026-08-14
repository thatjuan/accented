import AppKit
import Carbon.HIToolbox
import os

/// Long-lived owner of the accent picker panel. `show()` / `orderOut` lifecycle; one
/// instance on `AppCoordinator`.
@MainActor
final class PickerWindowController: NSWindowController, NSWindowDelegate {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Picker")

    var onCommit: ((AccentVariant, PickerContext) -> Void)?
    var onDismiss: (() -> Void)?
    var onRequestPermissions: (() -> Void)?

    private let panel: PickerPanel
    private let effectView = NSVisualEffectView()
    private let content = PickerContentView()
    private var session: PickerSession?
    private var catalog = CharacterCatalog()
    private var clickMonitor: Any?
    private var isCommitting = false
    /// `makeKey` on an accessory app often posts an immediate resign as the previous
    /// app keeps active. Ignore that first one so we do not orderOut a just-shown panel.
    private var ignoreResignUntil: Date?

    var isVisible: Bool { panel.isVisible }

    init() {
        let panel = PickerPanel()
        self.panel = panel
        super.init(window: panel)

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = PickerContentView.Layout.cornerRadius
        effectView.layer?.masksToBounds = true

        content.wantsLayer = true
        content.onSelectCell = { [weak self] row, col in
            self?.select(row: row, column: col)
        }
        content.onCommitCell = { [weak self] _, _ in
            self?.commitSelection()
        }
        content.onBannerClick = { [weak self] in
            self?.dismiss()
            self?.onRequestPermissions?()
        }

        effectView.addSubview(content)
        panel.contentView = effectView
        panel.onKeyDown = { [weak self] event in
            self?.handleKey(event)
        }
        panel.delegate = self
    }

    func windowDidResignKey(_ notification: Notification) {
        if let until = ignoreResignUntil, Date() < until { return }
        if !isCommitting { dismiss() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(context: PickerContext, catalog: CharacterCatalog, degraded: Bool) {
        guard var built = PickerSession.build(context: context, catalog: catalog) else {
            logger.notice("Picker not shown — catalog produced no cells")
            return
        }
        self.catalog = catalog
        built.selectedRow = 0
        built.selectedColumn = 0
        session = built
        content.session = built
        content.showsDegradedBanner = degraded
        layoutAndPosition(caretRect: context.caretRect)
        present()
        installClickOutsideMonitor()
        logger.info("Picker shown mode=\(String(describing: context.mode), privacy: .public) degraded=\(degraded, privacy: .public) frame=\(NSStringFromRect(self.panel.frame), privacy: .public) key=\(self.panel.isKeyWindow, privacy: .public)")
    }

    func dismiss() {
        tearDownClickOutsideMonitor()
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        session = nil
        logger.info("Picker dismissed")
        onDismiss?()
    }

    // MARK: - Layout

    private func layoutAndPosition(caretRect: CGRect?) {
        let size = PickerContentView.size(for: content.session, banner: content.showsDegradedBanner)
        content.frame = NSRect(origin: .zero, size: size)
        effectView.frame = content.frame
        panel.setContentSize(size)

        let mouse = NSEvent.mouseLocation
        let screenFrames = NSScreen.screens.map(\.frame)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = PickerPlacement.usableCaret(caretRect, screens: screenFrames)
        let frame = PickerPlacement.frame(
            size: size,
            caretRect: caret,
            mouse: mouse,
            screen: screen
        )
        panel.setFrame(frame, display: true)
    }

    /// Accessory + `.nonactivatingPanel`: `makeKeyAndOrderFront` does not raise the
    /// window above the frontmost app. `orderFrontRegardless` does, without activating
    /// us (the target field keeps its focus ring). Then `makeKey` so arrows / numbers work.
    private func present() {
        ignoreResignUntil = Date().addingTimeInterval(0.3)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    // MARK: - Input

    private func handleKey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty, let chars = event.charactersIgnoringModifiers, let first = chars.first,
           first.isNumber, let n = Int(String(first)), (1...9).contains(n) {
            if let variant = session?.variant(forNumber: n) {
                commit(variant)
            }
            return
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            dismiss()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commitSelection()
        case kVK_LeftArrow:
            mutate { $0.moveHorizontal(-1) }
        case kVK_RightArrow:
            mutate { $0.moveHorizontal(1) }
        case kVK_UpArrow:
            mutate { $0.moveVertical(-1) }
        case kVK_DownArrow:
            mutate { $0.moveVertical(1) }
        default:
            if flags.subtracting(.shift).isEmpty,
               let chars = event.charactersIgnoringModifiers,
               let letter = chars.first,
               letter.isLetter {
                applyBrowseLetter(letter)
            }
        }
    }

    private func applyBrowseLetter(_ letter: Character) {
        guard var session else { return }
        switch session.handleBrowseLetter(letter, catalog: catalog) {
        case .ignored:
            break
        case .filtered:
            self.session = session
            content.session = session
        case .commit(let variant):
            commit(variant)
        }
    }

    private func select(row: Int, column: Int) {
        mutate { $0.select(row: row, column: column) }
    }

    private func commitSelection() {
        guard let variant = session?.selectedVariant else { return }
        commit(variant)
    }

    private func commit(_ variant: AccentVariant) {
        guard let context = session?.context else { return }
        isCommitting = true
        // Spike: orderOut first, then commit on the next run-loop turn.
        dismiss()
        let pending = variant
        let ctx = context
        DispatchQueue.main.async { [weak self] in
            self?.onCommit?(pending, ctx)
            self?.isCommitting = false
        }
    }

    private func mutate(_ body: (inout PickerSession) -> Void) {
        guard var session else { return }
        body(&session)
        self.session = session
        content.session = session
    }

    private func installClickOutsideMonitor() {
        tearDownClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }

    private func tearDownClickOutsideMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }
}
