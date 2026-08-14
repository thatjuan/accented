import AppKit
import os

/// Application delegate: owns the main menu and the app-wide coordinator seam. Kept deliberately
/// thin — feature wiring (hotkey, picker, insertion, settings, Sparkle) lives in `AppCoordinator`
/// and the per-feature types added by later issues.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "AppDelegate")

    /// Central seam for later issues (#4 hotkey, #5 permissions, #6 picker, #7 insertion, #8
    /// settings, #9 Sparkle). Created up front so launch gates can consult it before any UI.
    private let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Accented launching")

        // Single-instance guard (diarc #42). Two Accented instances would register two hotkeys
        // and post two CGEvent streams — they'd fight. LaunchServices already dedupes
        // `open Accented.app`, but NOT `open -n`, a direct binary exec, or two same-id copies.
        // Bail BEFORE building any UI if another instance of our bundle id is already running.
        // (A simultaneous double-launch race could pass this in the same instant — not worth a
        // distributed lock for this utility; the real case is a manual second launch.)
        if let existing = otherRunningInstance() {
            logger.notice("Another Accented instance is already running (pid \(existing.processIdentifier, privacy: .public)); activating it and quitting")
            existing.activate()
            NSApp.terminate(nil)
            return
        }

        buildMainMenu()
        coordinator.start()

        // #5: a granted launch opens nothing. Onboarding appears only when Accessibility
        // is actually missing. `start()` already refreshed via `beginMonitoring()`.
        if coordinator.permissions.isDegraded {
            logger.info("Accessibility not granted at launch — showing onboarding")
            coordinator.showOnboarding()
        }
    }

    /// Any *other* already-running instance of Accented's own bundle id (excludes this process),
    /// or `nil`. Falls back to the literal bundle id if `Bundle.main.bundleIdentifier` is
    /// unexpectedly nil (e.g. a bare binary launched outside the .app wrapper).
    private func otherRunningInstance() -> NSRunningApplication? {
        let bundleID = Bundle.main.bundleIdentifier ?? AppIdentity.bundleID
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0 != .current }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu-bar app: closing Settings / onboarding must NOT quit. Quit is explicit
        // (status menu / Cmd-Q).
        return false
    }

    // MARK: - Settings / updates (forwarded to the coordinator)

    /// Open Settings via the coordinator (#8). Fired by the App-menu item (Cmd-,) and the
    /// status-item menu.
    @objc func openSettings(_ sender: Any?) {
        coordinator.showSettings()
    }

    /// Check for updates via the coordinator. Stub until Sparkle lands in #9; the status-item
    /// and App-menu items share this action so #9 can retarget them together.
    @objc func checkForUpdates(_ sender: Any?) {
        coordinator.checkForUpdates()
    }

    @objc func openPermissions(_ sender: Any?) {
        coordinator.showOnboarding()
    }

    // MARK: - Main menu

    /// Build a minimal but correct main menu programmatically (no MainMenu.xib in a SwiftPM
    /// executable). Provides the standard App menu (About / Settings / Hide / Quit), Edit, and
    /// Window menus so the app behaves like a conventional macOS app once a window (Settings,
    /// onboarding) is key, and standard shortcuts (Cmd-Q, Cmd-, , copy / paste) work.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())

        let settingsItem = appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        appMenu.addItem(.separator())

        // Stub until #9 wires this to SPUStandardUpdaterController.checkForUpdates(_:).
        let checkForUpdatesItem = appMenu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        appMenu.addItem(.separator())

        let hideItem = appMenu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.keyEquivalentModifierMask = [.command]

        let hideOthersItem = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())

        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        // Edit menu — standard responder-chain editing actions so text fields behave.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSResponder.selectAll(_:)),
            keyEquivalent: "a"
        )

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        let permissionsItem = helpMenu.addItem(
            withTitle: "Permissions…",
            action: #selector(openPermissions(_:)),
            keyEquivalent: ""
        )
        permissionsItem.target = self

        if DiagnosticsMenuGate.isEnabled {
            buildDiagnosticsMenu(into: mainMenu)
        }

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    /// Diagnostics menu (#2 insertion-fidelity harness) — installed ONLY when the launch
    /// environment opts in (`ACCENTED_DIAGNOSTICS=1` or `--diagnostics`). Posts real synthetic
    /// events to the frontmost app, so it is hidden from normal product UX. Accessory apps have
    /// no visible menu bar; the same items also live on the status-item menu.
    private func buildDiagnosticsMenu(into mainMenu: NSMenu) {
        logger.notice("Diagnostics menu ENABLED (#2 insertion-fidelity harness)")
        let diagnosticsItem = NSMenuItem()
        mainMenu.addItem(diagnosticsItem)
        let diagnosticsMenu = NSMenu(title: "Diagnostics")
        diagnosticsItem.submenu = diagnosticsMenu

        let header = diagnosticsMenu.addItem(
            withTitle: "Insertion fidelity (#2) — posts REAL events to the frontmost app",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        diagnosticsMenu.addItem(.separator())

        for probeCase in InsertionFidelityProbe.Case.allCases {
            let item = diagnosticsMenu.addItem(
                withTitle: probeCase.title,
                action: #selector(runProbeCase(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = probeCase.rawValue
        }
    }

    @objc private func runProbeCase(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let probeCase = InsertionFidelityProbe.Case(rawValue: rawValue) else {
            logger.error("Diagnostics: menu item has no valid probe case in representedObject")
            return
        }
        coordinator.insertionFidelityProbe.run(probeCase)
    }
}
