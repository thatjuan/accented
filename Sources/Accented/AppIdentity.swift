/// Bundle identity shared by the running app, the single-instance guard, and tests.
///
/// `Bundle.main.bundleIdentifier` is the runtime source of truth inside a packaged `.app`.
/// This constant is the fallback when the binary is launched unpackaged (SwiftPM
/// `.build/debug/Accented`) and the value tests assert against.
enum AppIdentity {
    static let bundleID = "com.thatjuan.accented"
}
