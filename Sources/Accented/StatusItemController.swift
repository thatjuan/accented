import AppKit
import os

/// Owns the menu-bar `NSStatusItem` and its menu.
///
/// Diarc has no status item (it lives on the floating switcher). Accented is a Dock-less
/// menu-bar app, so this controller is the primary way to reach Show Picker, Settings,
/// Check for Updates, and Quit. "Show Picker" fires the same coordinator entry point the
/// global hotkey (#4) will use.
@MainActor
final class StatusItemController: NSObject {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "StatusItem")

    private var statusItem: NSStatusItem?

    var onShowPicker: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // "á" is the product: an accented letter, readable as a template-ish title in both
            // appearances. A custom template image can replace this once the real icon ships.
            button.title = "á"
            button.toolTip = "Accented"
        }
        item.menu = Self.makeMenu(target: self)
        statusItem = item
        logger.info("Status item installed")
    }

    /// Builds the status-item menu. Internal so tests can assert titles and key equivalents
    /// without installing a real status item.
    static func makeMenu(target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        let showPicker = menu.addItem(
            withTitle: "Show Picker",
            action: #selector(showPicker(_:)),
            keyEquivalent: ""
        )
        showPicker.target = target

        menu.addItem(.separator())

        let settings = menu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = target

        let updates = menu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updates.target = target

        menu.addItem(.separator())

        let quit = menu.addItem(
            withTitle: "Quit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = target

        return menu
    }

    @objc private func showPicker(_ sender: Any?) {
        logger.info("Status menu: Show Picker")
        onShowPicker?()
    }

    @objc private func showSettings(_ sender: Any?) {
        logger.info("Status menu: Settings")
        onShowSettings?()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        logger.info("Status menu: Check for Updates")
        onCheckForUpdates?()
    }

    @objc private func quit(_ sender: Any?) {
        logger.info("Status menu: Quit")
        onQuit?()
    }
}
