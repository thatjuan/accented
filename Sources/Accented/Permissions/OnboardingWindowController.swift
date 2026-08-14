import AppKit
import SwiftUI
import os

/// First-run welcome: why Accessibility is needed, live granted/denied badge, Grant Access
/// + Open System Settings, and a Get Started button that dismisses once granted.
///
/// Port of diarc `OnboardingWindowController` — SwiftUI in `NSHostingController`, fixed
/// portrait window, `isReleasedWhenClosed = false` so Help → Permissions… can re-show it.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "Onboarding")
    private let permissions: PermissionsManager

    init(permissions: PermissionsManager) {
        self.permissions = permissions

        var controller: OnboardingWindowController!
        let hosting = NSHostingController(
            rootView: OnboardingView(
                permissions: permissions,
                hotkeyLabel: HotkeyDefaults.load().displayString,
                onDismiss: { controller?.close() }
            )
        )
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: OnboardingView.windowSize.width,
                                height: OnboardingView.windowSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Accented"
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.center()

        super.init(window: window)
        controller = self
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OnboardingWindowController does not support NSCoder")
    }

    override func showWindow(_ sender: Any?) {
        logger.info("Showing onboarding window")
        permissions.startOnboardingPoll()
        NSApp.activate(ignoringOtherApps: true)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        permissions.stopOnboardingPoll()
    }
}

/// Portrait welcome pane. Observes `PermissionsManager` so the badge flips live.
struct OnboardingView: View {

    @ObservedObject var permissions: PermissionsManager
    var hotkeyLabel: String
    let onDismiss: () -> Void

    static let windowSize = CGSize(width: 420, height: 560)

    private var granted: Bool { permissions.accessibility.isGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            permissionCard
            steps
            Spacer(minLength: 8)
            footer
        }
        .padding(28)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to Accented")
                        .font(.title.weight(.bold))
                    Text("Accents, on your terms.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Text("Accented needs the Accessibility permission to see your text cursor and type characters for you.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accessibility")
                    .font(.headline)
                Text("Required")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer(minLength: 12)
                statusBadge
            }

            if !granted {
                HStack(spacing: 10) {
                    Button("Grant Access") { _ = permissions.requestAccessibility() }
                        .keyboardShortcut(.defaultAction)
                    Button("Open System Settings…") { permissions.openAccessibilitySettings() }
                }
                .controlSize(.large)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private var statusBadge: some View {
        Label(granted ? "Granted" : "Not granted",
              systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundColor(granted ? .green : .orange)
            .labelStyle(.titleAndIcon)
            .fixedSize()
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "Grant Accessibility above.")
            step(2, "Type a letter in any app.")
            step(3, "Press \(hotkeyLabel) and pick a variant.")
            Text("Try it: type `a` in any app, press \(hotkeyLabel).")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.semibold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
            Text(text)
                .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(granted ? "Get Started" : "Continue") { onDismiss() }
                .controlSize(.large)
                .keyboardShortcut(granted ? .defaultAction : .cancelAction)
                .disabled(!granted)
        }
    }
}
