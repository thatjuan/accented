@testable import Accented

#if canImport(Testing)
import AppKit
import ApplicationServices
import Sparkle
import Testing

/// Status-item menu contract (#1). Titles and the Settings key equivalent are the product surface
/// later issues (#4/#8/#9) plug into — pin them so a rename can't silently break the status menu.
///
/// These tests compile only when the Swift Testing module is visible (full Xcode toolchain).
/// CommandLineTools has no XCTest/Testing, so `swift test` there still passes via the
/// `@testable import` link check below.
@Suite
struct StatusMenuTests {

    @Test @MainActor
    func menuItemsInOrder() {
        let menu = StatusItemController.makeMenu(target: NSObject())
        let titles = menu.items.map(\.title)
        #expect(titles == [
            "Show Picker",
            "",
            "Settings…",
            "Check for Updates…",
            "",
            "Help",
            "",
            "Quit",
        ])
        let help = menu.items.first { $0.title == "Help" }?.submenu
        #expect(help?.items.map(\.title) == ["Permissions…"])
    }

    @Test @MainActor
    func checkForUpdatesUsesSparkleTargetWhenSet() {
        let controller = StatusItemController()
        let sparkle = NSObject()
        controller.updatesTarget = sparkle
        let menu = StatusItemController.makeMenu(target: controller)
        let updates = menu.items.first { $0.title == "Check for Updates…" }
        #expect(updates?.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        #expect(updates?.target === sparkle)
    }

    @Test @MainActor
    func settingsUsesCommandComma() {
        let menu = StatusItemController.makeMenu(target: NSObject())
        let settings = menu.items.first { $0.title == "Settings…" }
        #expect(settings?.keyEquivalent == ",")
        #expect(settings?.keyEquivalentModifierMask == [.command])
    }

    @Test
    func bundleIdentity() {
        #expect(AppIdentity.bundleID == "com.thatjuan.accented")
    }

    @Test
    func permissionStatusGrantedFlag() {
        #expect(PermissionStatus.granted.isGranted)
        #expect(!PermissionStatus.denied.isGranted)
    }

    @Test @MainActor
    func permissionsRefreshMatchesSystem() {
        let manager = PermissionsManager()
        manager.refresh()
        #expect(manager.accessibility.isGranted == AXIsProcessTrusted())
        #expect(manager.isDegraded == !AXIsProcessTrusted())
    }

    @Test
    func diagnosticsGateDefaultsOff() {
        // Tests don't pass ACCENTED_DIAGNOSTICS / --diagnostics, so the product menu stays clean.
        #expect(DiagnosticsMenuGate.isEnabled == false)
    }
}

#else

/// CommandLineTools doesn't expose XCTest or Testing. Keeping a `@testable import` reference
/// means `swift test` still builds and links the app module.
enum ScaffoldLinkCheck {
    static let bundleID = AppIdentity.bundleID
}

#endif
