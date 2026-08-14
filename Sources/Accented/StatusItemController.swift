import AppKit
import os
import Sparkle

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
    var onShowPermissions: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    /// When set, "Check for Updates…" uses Sparkle's standard action (auto enable/disable).
    var updatesTarget: AnyObject?
    var onQuit: (() -> Void)?
    /// Set only when `DiagnosticsMenuGate` is on. The status menu is the reachable surface for
    /// an accessory app (no visible menu bar).
    var onRunProbe: ((InsertionFidelityProbe.Case) -> Void)?

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Pin the extra so macOS doesn't restore it as hidden / off-canvas from a
        // previous launch (Ventura+ persists visibility under this name).
        item.autosaveName = "AccentedStatusItem"
        item.isVisible = true
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
        if let controller = target as? StatusItemController, let updatesTarget = controller.updatesTarget {
            updates.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
            updates.target = updatesTarget
        } else {
            updates.target = target
        }

        menu.addItem(.separator())

        let helpItem = menu.addItem(withTitle: "Help", action: nil, keyEquivalent: "")
        let help = NSMenu(title: "Help")
        helpItem.submenu = help
        let permissions = help.addItem(
            withTitle: "Permissions…",
            action: #selector(showPermissions(_:)),
            keyEquivalent: ""
        )
        permissions.target = target

        menu.addItem(.separator())

        let quit = menu.addItem(
            withTitle: "Quit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = target

        if DiagnosticsMenuGate.isEnabled {
            menu.addItem(.separator())
            let diagItem = menu.addItem(withTitle: "Diagnostics", action: nil, keyEquivalent: "")
            let diag = NSMenu(title: "Diagnostics")
            diagItem.submenu = diag
            for probeCase in InsertionFidelityProbe.Case.allCases {
                let item = diag.addItem(
                    withTitle: probeCase.title,
                    action: #selector(runProbe(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.representedObject = probeCase.rawValue
            }
        }

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

    @objc private func showPermissions(_ sender: Any?) {
        logger.info("Status menu: Help → Permissions")
        onShowPermissions?()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        logger.info("Status menu: Check for Updates")
        onCheckForUpdates?()
    }

    @objc private func quit(_ sender: Any?) {
        logger.info("Status menu: Quit")
        onQuit?()
    }

    @objc private func runProbe(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let probeCase = InsertionFidelityProbe.Case(rawValue: raw) else {
            logger.error("Diagnostics: menu item has no valid probe case")
            return
        }
        logger.notice("Status menu: Diagnostics \(probeCase.title, privacy: .public)")
        onRunProbe?(probeCase)
    }
}
