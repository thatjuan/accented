import AppKit

/// Brief "Copied — press ⌘V" after a degraded-mode commit. Not a picker; just a HUD.
@MainActor
enum CopiedToast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show() {
        hideWork?.cancel()
        let panel = ensurePanel()
        if let mouse = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            var frame = panel.frame
            frame.origin = NSPoint(
                x: mouse.visibleFrame.midX - frame.width / 2,
                y: mouse.visibleFrame.minY + 80
            )
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
        let work = DispatchWorkItem {
            panel.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private static func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 8
        blur.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "Copied — press ⌘V")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.frame = blur.bounds
        label.autoresizingMask = [.width, .height]
        blur.addSubview(label)
        panel.contentView = blur
        self.panel = panel
        return panel
    }
}
