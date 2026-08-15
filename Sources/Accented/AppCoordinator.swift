import AppKit
import Combine
import os
import Sparkle

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

    /// Shared settings (#8). One instance app-wide; picker, hotkey, and Settings all read it.
    let settingsStore = SettingsStore()

    /// Shared Accessibility state (#5). Observed by onboarding; #6/#7 read `isDegraded`.
    let permissions = PermissionsManager()

    private var onboardingWindowController: OnboardingWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    /// Sparkle updater. Held for the app's lifetime so `NSMenuItem.target` (weak) stays live
    /// and scheduled checks keep running. `startingUpdater: true` starts on first access.
    private(set) lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private let pickerController = PickerWindowController()
    private lazy var insertionEngine: InsertionEngine = DefaultInsertionEngine(
        catalog: { [weak self] in self?.settingsStore.makeCatalog() ?? CharacterCatalog() },
        isDegraded: { [weak self] in self?.permissions.isDegraded ?? true },
        bumpUsage: { [weak self] glyph in self?.settingsStore.bumpUsage(glyph) }
    )

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
        statusItemController.updatesTarget = updaterController
        statusItemController.onQuit = {
            NSApp.terminate(nil)
        }
        settingsStore.$hotkey
            .sink { [weak self] hotkey in
                self?.hotkeyManager.register([.picker: hotkey])
            }
            .store(in: &cancellables)
        settingsStore.$doubleTapModifier
            .sink { [weak self] mode in
                self?.hotkeyManager.setDoubleTap(mode)
            }
            .store(in: &cancellables)
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
        settingsStore.automaticallyChecksForUpdates =
            updaterController.updater.automaticallyChecksForUpdates
        settingsStore.$automaticallyChecksForUpdates
            .sink { [weak self] enabled in
                self?.updaterController.updater.automaticallyChecksForUpdates = enabled
            }
            .store(in: &cancellables)
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
            catalog: settingsStore.makeCatalog(),
            degraded: permissions.isDegraded
        )
    }

    /// Open Settings (⌘, / status menu). Reused across opens.
    func showSettings() {
        logger.info("Settings requested")
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                store: settingsStore,
                permissions: permissions,
                checkForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) }
            )
        }
        settingsWindowController?.showWindow(nil)
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

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
