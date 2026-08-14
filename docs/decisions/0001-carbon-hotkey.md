# ADR 0001 — Carbon `RegisterEventHotKey` for the global trigger

- **Status:** Accepted
- **Date:** 2026-08-14
- **Part of:** issue **#4** (global hotkey engine + recorder)
- **Coordinates with:** issue **#6** (picker, same fire entry as the status item), issue **#8**
  (`SettingsStore` persistence of key code + modifiers)

## Context

Accented needs a global hotkey that works with any app frontmost, including full-screen apps,
**before** Accessibility is granted. The picker can still appear near the mouse in degraded
mode (#5); the hotkey itself must not depend on Input Monitoring or an event tap.

Two usual mechanisms:

1. **`CGEventTap`** on the session tap — sees every keystroke. Needs Input Monitoring (a second
   TCC grant next to Accessibility). Adds a callback to the input path. Secure-input fields
   (password prompts) go dark and the tap sees nothing.
2. **Carbon `RegisterEventHotKey`** — the system watches one combo. No Input Monitoring. No
   per-keystroke cost. Still delivered during secure input.

Diarc has no hotkey code. This is new, but the Carbon path is the long-standing one used by
Spotlight-style utilities.

## Decision

**Use `RegisterEventHotKey` / `UnregisterEventHotKey`.** Do not install a `CGEventTap` for the
trigger.

- Default combo: **⌥Space** (`kVK_Space` + `optionKey`). Unused by stock macOS, mnemonic.
- One slot in v1 (`Hotkey.Slot.picker`). The manager API is a `[Slot: Hotkey]` map so a second
  binding stays a one-liner later — we do not build that binding now.
- Fire is a closure on `HotkeyManager`, pointed at `AppCoordinator.showPicker()` — the same
  entry as the status-item "Show Picker" action.
- Persist as `settings.hotkeyKeyCode` + `settings.hotkeyModifiers` (AppKit modifier raw
  values). `#8` takes these keys as-is.
- Unregister on quit (`applicationWillTerminate`) so a dead process cannot leave a ghost.

A `CGEventTap` is reserved for things that actually need every key (#7 does not: it posts
events, it does not listen).

## Consequences

- No Input Monitoring prompt for the hotkey. Accessibility is still required for caret
  insertion (#6/#7), not for showing the picker.
- Combos the system already owns (`⌘Space`, `⌘Tab`, …) will fail `RegisterEventHotKey` or
  never reach us; the recorder also deny-lists ⌘Q / ⌘W / ⌘Space and bare letters.
- Layout-specific glyphs in the recorder come from `UCKeyTranslate` on the current input
  source; registration itself is by virtual key code, so a physical key stays put if the
  user switches layouts.
- We did not take a library (KeyboardShortcuts). The surface is one combo and a small
  deny-list; a dependency would be heavier than the Carbon calls.

## Alternatives considered

- **`CGEventTap`:** rejected — extra TCC, extra latency, dies in secure input.
- **`NSEvent.addGlobalMonitorForEvents`:** cannot consume the event, so ⌥Space would also
  type a space into the target field.
- **sindresorhus/KeyboardShortcuts:** fine if the recorder gets painful. It did not.
