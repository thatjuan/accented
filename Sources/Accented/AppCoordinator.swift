import AppKit
import os

/// Top-level coordinator and the primary seam between issues. Issue #1 wires only what's needed
/// to launch and to own the status item; later issues hang their subsystems off this object:
///
///   - #4  `HotkeyManager` — on fire, calls `showPicker()` (same entry as the status item)
///   - #5  `PermissionsManager` + onboarding window
///   - #6  picker panel controller
///   - #7  caret-context + insertion engine
///   - #8  `SettingsStore` + Settings window
///   - #9  `SPUStandardUpdaterController` (held for the app's lifetime; `NSMenuItem.target` is weak)
///
/// Keeping this here means the AppDelegate stays a thin lifecycle shim and feature owners have a
/// single, obvious place to plug in.
///
/// ## Concurrency
/// `@MainActor`. All AppKit wiring runs on the main actor.
@MainActor
final class AppCoordinator {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "AppCoordinator")

    /// Menu-bar status item. Owned here so it lives for the app's lifetime.
    private let statusItemController = StatusItemController()

    /// Insertion-fidelity harness (#2). Owned for the app's lifetime so the Diagnostics menu's
    /// weak `target` stays live. Only reached when `DiagnosticsMenuGate` is on.
    private(set) lazy var insertionFidelityProbe = InsertionFidelityProbe()

    func start() {
        logger.info("Coordinator starting")
        statusItemController.onShowPicker = { [weak self] in
            self?.showPicker()
        }
        statusItemController.onShowSettings = { [weak self] in
            self?.showSettings()
        }
        statusItemController.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        statusItemController.onQuit = {
            NSApp.terminate(nil)
        }
        if DiagnosticsMenuGate.isEnabled {
            logger.notice("Diagnostics gate ON — insertion-fidelity probe menu will be installed")
            statusItemController.onRunProbe = { [weak self] probeCase in
                self?.insertionFidelityProbe.run(probeCase)
            }
        }
        statusItemController.install()
    }

    /// Shared entry point for the status-item "Show Picker" action and (later) the global hotkey
    /// (#4). The picker panel itself arrives in #6.
    func showPicker() {
        logger.info("Show Picker requested (picker panel arrives in #6)")
    }

    /// Open the Settings window (#8). Stub until that issue lands.
    func showSettings() {
        logger.info("Settings requested (window arrives in #8)")
    }

    /// Check for updates (#9). Stub until Sparkle is wired; #9 retargets the menu item at
    /// `SPUStandardUpdaterController.checkForUpdates(_:)` and holds the controller here.
    func checkForUpdates() {
        logger.info("Check for Updates requested (Sparkle arrives in #9)")
    }
}
