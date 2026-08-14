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

    /// Shared Accessibility state (#5). Observed by onboarding; #6/#7 read `isDegraded`.
    let permissions = PermissionsManager()

    private var onboardingWindowController: OnboardingWindowController?

    private let pickerController = PickerWindowController()
    private lazy var insertionEngine: InsertionEngine = DefaultInsertionEngine(
        catalog: { [weak self] in self?.liveCatalog() ?? CharacterCatalog() },
        isDegraded: { [weak self] in self?.permissions.isDegraded ?? true }
    )

    /// Catalog with persisted MRU tallies so #8 can flip `orderingMode` without a new key.
    private func liveCatalog() -> CharacterCatalog {
        CharacterCatalog(usageCounts: UsageCounts.load())
    }

    func start() {
        logger.info("Coordinator starting")
        statusItemController.onShowPicker = { [weak self] in
            self?.showPicker()
        }
        statusItemController.onShowSettings = { [weak self] in
            self?.showSettings()
        }
        statusItemController.onShowPermissions = { [weak self] in
            self?.showOnboarding()
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
        pickerController.onCommit = { [weak self] variant, context in
            self?.insertionEngine.commit(variant, for: context)
            if self?.permissions.isDegraded == true {
                CopiedToast.show()
            }
        }
        pickerController.onRequestPermissions = { [weak self] in
            self?.showOnboarding()
        }
        hotkeyManager.start()
        permissions.beginMonitoring()
        if DiagnosticsMenuGate.isEnabled {
            logger.notice("Diagnostics gate ON — insertion-fidelity probe menu will be installed")
            statusItemController.onRunProbe = { [weak self] probeCase in
                self?.insertionFidelityProbe.run(probeCase)
            }
        }
        statusItemController.install()
    }

    /// Shared entry point for the status-item "Show Picker" action and the global hotkey.
    /// A second press while the panel is up dismisses it.
    func showPicker() {
        if pickerController.isVisible {
            logger.info("Picker already open — dismissing")
            pickerController.dismiss()
            return
        }
        permissions.refresh()
        let context = insertionEngine.currentContext()
        logger.info("Showing picker")
        pickerController.show(
            context: context,
            catalog: liveCatalog(),
            degraded: permissions.isDegraded
        )
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

    /// First-run / Help → Permissions…. Safe to call when already granted (the window
    /// still explains the grant and shows the live badge).
    func showOnboarding() {
        logger.info("Onboarding requested (granted=\(self.permissions.accessibility.isGranted, privacy: .public))")
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(permissions: permissions)
        }
        onboardingWindowController?.showWindow(nil)
    }

    /// Drop Carbon registrations so a quit leaves no ghost hotkey.
    func stop() {
        permissions.stopOnboardingPoll()
        hotkeyManager.stop()
    }

    /// Check for updates (#9). Stub until Sparkle is wired; #9 retargets the menu item at
    /// `SPUStandardUpdaterController.checkForUpdates(_:)` and holds the controller here.
    func checkForUpdates() {
        logger.info("Check for Updates requested (Sparkle arrives in #9)")
    }
}
