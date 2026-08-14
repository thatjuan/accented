import AppKit
import ApplicationServices
import Combine
import os

/// Authorization status for a single TCC-gated capability.
enum PermissionStatus: Equatable, Sendable {
    /// Granted — the capability can be used now.
    case granted
    /// Not yet granted (denied, or never requested).
    case denied

    var isGranted: Bool { self == .granted }
}

/// Tracks Accented's Accessibility grant and surfaces it as observable state for onboarding
/// and (later) for the picker / insertion engine to gate on.
///
/// Accessibility is required for caret reads and `CGEvent` posting (#6/#7). The hotkey (#4)
/// does **not** need it — `RegisterEventHotKey` is permission-free — so a denied launch still
/// has a live trigger.
///
/// ## Degraded mode (#6/#7 contract)
/// When `!accessibility.isGranted` (`isDegraded == true`):
///   - the hotkey still opens the picker, positioned near the mouse (`caretRect = nil`)
///   - commit falls back to pasteboard-copy + a toast "Copied — press ⌘V"
///   - the picker shows a one-line banner that opens this permission flow
/// The app must never look dead before the grant lands. This type only publishes the flag;
/// #6/#7 implement the fallback UI.
///
/// Re-checked on `NSApplication.didBecomeActiveNotification`. Accessory apps often never
/// become active while the user is in System Settings, so `startOnboardingPoll()` also ticks
/// while the onboarding window is visible.
@MainActor
final class PermissionsManager: ObservableObject {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Permissions")

    /// Current Accessibility (AX) trust state.
    @Published private(set) var accessibility: PermissionStatus = .denied

    /// `#6/#7` shortcut: picker still opens, but insert/replace cannot use AX/CGEvent.
    var isDegraded: Bool { !accessibility.isGranted }

    private var didBecomeActiveObserver: NSObjectProtocol?
    private var onboardingPoll: Timer?

    deinit {
        if let token = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(token)
        }
        onboardingPoll?.invalidate()
    }

    // MARK: - Monitoring

    /// Begin observing app activation to re-check permissions live, and perform an initial refresh.
    /// Idempotent — safe to call once from the coordinator.
    func beginMonitoring() {
        if didBecomeActiveObserver == nil {
            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
        refresh()
    }

    /// Re-read Accessibility from the system (non-prompting) and publish any change.
    func refresh() {
        let ax: PermissionStatus = AXIsProcessTrusted() ? .granted : .denied
        if ax != accessibility {
            logger.info("Accessibility permission changed -> \(ax.isGranted ? "granted" : "denied", privacy: .public)")
            accessibility = ax
        }
    }

    /// Poll while onboarding is on screen. `didBecomeActive` never fires for an accessory
    /// app the user does not click back into after flipping the System Settings toggle.
    func startOnboardingPoll() {
        guard onboardingPoll == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.15
        onboardingPoll = timer
        logger.info("Onboarding poll started")
    }

    func stopOnboardingPoll() {
        onboardingPoll?.invalidate()
        onboardingPoll = nil
    }

    // MARK: - Requests

    /// Request Accessibility trust. The prompt option shows the system dialog (and adds
    /// Accented to the Accessibility list) when not already trusted. The grant happens
    /// asynchronously; `didBecomeActive` and the onboarding poll observe the result.
    @discardableResult
    func requestAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibility = trusted ? .granted : .denied
        logger.info("Requested Accessibility; trusted=\(trusted, privacy: .public)")
        return trusted
    }

    /// Open the Accessibility privacy pane in System Settings.
    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: urlString) else {
            logger.error("Malformed System Settings URL: \(urlString, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
