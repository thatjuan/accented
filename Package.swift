// swift-tools-version:6.0
import PackageDescription

// Accented — SwiftPM executable + hand-assembled .app bundle (no Xcode in this environment).
//
// Language-mode decision:
//   The manifest uses swift-tools-version 6.0 (modern PackageDescription: lets us declare
//   `swiftLanguageModes` and per-target settings), but the target is pinned to the **Swift 5
//   language mode** (`swiftLanguageModes: [.v5]`). This deliberately defers Swift 6 strict
//   concurrency. Issue #1 is pure AppKit @MainActor scaffolding where strict concurrency adds
//   only friction; the real concurrency surface (Carbon hotkey callbacks in #4, AX/CGEvent work
//   in #6/#7) arrives later, at which point individual targets can be flipped to `.v6` once
//   their actor boundaries are designed. Compiles cleanly on the Swift 6 toolchain in Swift 5
//   mode.
//
// Platform: macOS 13 (.v13). A comfortable floor that gives us modern AppKit APIs (and matches
// diarc). LSMinimumSystemVersion in Info.plist mirrors this.
let package = Package(
    name: "Accented",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Accented",
            path: "Sources/Accented",
            // Info.plist and the app icon live under Sources/Accented/ but are copied into the
            // bundle by Scripts/package.sh, not embedded by SwiftPM. Exclude them from the build
            // graph so SwiftPM doesn't treat them as processable resources. A SwiftPM `.copy`
            // would emit the icns into a nested `Accented_Accented.bundle`, which the
            // hand-assembled .app never picks up and which `CFBundleIconFile` doesn't read — so
            // the icon is delivered straight to Contents/Resources by package.sh instead,
            // mirroring the Info.plist handling.
            // `Resources/dmg/` holds the install-DMG background art — consumed by
            // Scripts/notarize.sh at DMG-build time, never embedded in the .app — so it is
            // excluded from the build graph too (else SwiftPM flags it as an unhandled resource).
            exclude: ["Info.plist", "Resources/AppIcon.icns", "Resources/dmg"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            // No Xcode "Embed Frameworks" phase exists in this hand-assembled bundle. The binary
            // is laid into Contents/MacOS/ (and Sparkle.framework into Contents/Frameworks/ by
            // package.sh, once #9 lands), so the dynamic loader needs an rpath of
            // @executable_path/../Frameworks to resolve
            // @rpath/Sparkle.framework/Versions/B/Sparkle at launch. Included now so #9 only
            // adds the framework copy + signing.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // Unit tests (Swift Testing — XCTest is not on CommandLineTools). `@testable import
        // Accented` reaches internal types; the test target pulls in no AX/hotkey dependency,
        // so it runs headless. Pinned to the Swift 5 language mode to match the app target.
        .testTarget(
            name: "AccentedTests",
            dependencies: ["Accented"],
            path: "Tests/AccentedTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
