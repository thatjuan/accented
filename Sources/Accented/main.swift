import AppKit

// Accented executable entry point.
//
// SwiftPM executables have no NSApplicationMain auto-wiring (that's an Xcode/Info.plist
// affordance). We wire the application by hand here: create the shared NSApplication, install our
// AppDelegate, set the .accessory activation policy (no Dock icon; LSUIElement=true), then run
// the event loop. `main.swift` enables top-level code, so this runs directly — note we
// intentionally do NOT use `@main`, which is mutually exclusive with a `main.swift` file.

// Top-level code in `main.swift` is nonisolated, but every line here touches main-actor-isolated
// AppKit state and genuinely runs on the main thread at process start. Assert that isolation
// explicitly so the @MainActor AppDelegate can be constructed without spurious actor-hop errors.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // .accessory: menu-bar utility — no Dock icon. Accented lives in an NSStatusItem; its
    // app-level actions (Show Picker, Settings, Check for Updates, Quit) are reached from that
    // menu. `LSUIElement` in Info.plist mirrors this. An `.accessory` app can still show and
    // focus ordinary windows (Settings, the permissions dialog).
    app.setActivationPolicy(.accessory)

    app.run()
}
