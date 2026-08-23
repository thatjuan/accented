# Accented

A tiny macOS menu bar utility that gives you the familiar press-and-hold accent picker, anywhere, on your terms.

macOS already shows an accent menu when you hold a vowel, but it is slow (you wait for the hold delay), it shows every possible diacritic for every language, and it doesn't work when key repeat is enabled. Accented replaces that flow with a global trigger and a picker that shows **only the characters relevant to the languages you actually write in**.

## How it works

1. You type normally. When you need an accented character, you press the global hotkey (default: `⌥ Space`, configurable).
2. A small floating picker appears at your text caret (or near the mouse if the caret can't be located), styled like the native macOS accent popover.
3. The picker is context-aware: if the character just before the caret is a base letter (`a`, `e`, `n`, `c`, ...), it shows that letter's enabled variants and, on selection, **replaces** the base letter (type `a`, hit the hotkey, pick `á`). If there is no matching base character, it shows your full enabled set in one horizontal row, and **inserts** the selection.
4. Selection works like the native menu: number keys `1–9`, arrow keys + `Return`, or click. `Esc` dismisses. Case follows the base character (`A` → `Á`).

## Customization

- **Language presets**: Spanish, French, Portuguese, German, Italian, Catalan, Turkish. Enable one or several; the picker shows the union of their characters. Spanish also includes `¿ ¡`; French includes `œ æ`; German includes `ß`.
- **Per-character control**: toggle individual characters off within a preset, or add your own custom characters/symbols.
- **Ordering**: most-used-first or fixed preset order.

## App shape

- Menu bar app (no Dock icon), SwiftUI settings window, launch at login, Sparkle auto-updates.
- Requires the Accessibility permission for the global hotkey, caret positioning, and character replacement; a short onboarding flow explains and requests it.
- Swift Package Manager project, no Xcode project file; scripted build, signing, notarization, and release (architecture borrowed from [diarc](https://github.com/thatjuan/diarc)).

## Status

App, packaging, Sparkle wiring, and the release/appcast Worker live in this repo. Live hosting and the first signed feed still need a dedicated EdDSA key (`SPARKLE_ED_KEY_FILE`) and the `accented.app` Cloudflare standup in `web/DEPLOY.md`.
