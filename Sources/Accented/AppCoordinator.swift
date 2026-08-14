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

    /// Global hotkey (#4). Owned here so registration lives for the app lifetime and
    /// `onFire` shares `showPicker()` with the status item.
    private let hotkeyManager = HotkeyManager()

    /// Stub Settings host until #8. Holds the recorder so a change re-registers immediately.
    private var hotkeySettingsWindow: HotkeySettingsWindowController?
    private let hotkeyStore = HotkeyStubStore(hotkey: HotkeyDefaults.load())

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
        hotkeyStore.onChange = { [weak self] hotkey in
            self?.hotkeyManager.register([.picker: hotkey])
        }
        hotkeyManager.onFire = { [weak self] _ in
            self?.showPicker()
        }
        hotkeyManager.start()
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

    /// Open the stub Settings window (hotkey recorder). Replaced by the real Settings in #8.
    func showSettings() {
        logger.info("Settings requested")
        if hotkeySettingsWindow == nil {
            hotkeySettingsWindow = HotkeySettingsWindowController(store: hotkeyStore)
        }
        hotkeyStore.hotkey = HotkeyDefaults.load()
        NSApp.activate(ignoringOtherApps: true)
        hotkeySettingsWindow?.showWindow(nil)
        hotkeySettingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    /// Drop Carbon registrations so a quit leaves no ghost hotkey.
    func stop() {
        hotkeyManager.stop()
    }

    /// Check for updates (#9). Stub until Sparkle is wired; #9 retargets the menu item at
    /// `SPUStandardUpdaterController.checkForUpdates(_:)` and holds the controller here.
    func checkForUpdates() {
        logger.info("Check for Updates requested (Sparkle arrives in #9)")
    }
}
