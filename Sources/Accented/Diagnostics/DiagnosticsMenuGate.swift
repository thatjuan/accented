import Foundation

/// Gate that decides whether the **Diagnostics** menu (the insertion-fidelity harness, issue #2)
/// is installed. The harness posts **real** synthetic events to the frontmost app, so it must
/// never be reachable in normal product UX — it is a measurement tool, not a feature.
///
/// Shown only when the launch environment opts in, so a normally-launched `Accented.app` never
/// exposes it. Two equivalent opt-ins (either is enough):
///   - environment variable `ACCENTED_DIAGNOSTICS=1`, or
///   - launch argument `--diagnostics`.
///
/// Typical use: `open dist/Accented.app --args --diagnostics`
enum DiagnosticsMenuGate {

    /// Environment variable opt-in (set to a non-empty, non-"0" value).
    static let environmentKey = "ACCENTED_DIAGNOSTICS"

    /// Launch-argument opt-in.
    static let launchArgument = "--diagnostics"

    /// Whether the Diagnostics menu should be installed for this launch.
    static var isEnabled: Bool {
        if let value = ProcessInfo.processInfo.environment[environmentKey],
           !value.isEmpty, value != "0" {
            return true
        }
        return ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}
