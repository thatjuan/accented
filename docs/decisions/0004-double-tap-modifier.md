# ADR 0004 — Modifier double-tap as a second picker trigger

- **Status:** Accepted
- **Date:** 2026-08-14
- **Part of:** issue **#21**
- **Depends on:** ADR 0001 (Carbon combo remains the primary trigger)

## Decision

Keep Carbon `RegisterEventHotKey` for combos (`⌥Space` by default). Add an **optional**
second trigger: two quick taps of ⌘ or ⌥, detected with `NSEvent` `flagsChanged`
monitors (global + local). **No `CGEventTap`.** Default is off.

Detection is a pure sequencer (`DoubleTapSequencer`):

- down → up → down → up of the watched modifier
- whole sequence inside 320ms
- each hold shorter than 180ms
- any other key, extra modifier, or mouse click resets

Left and right ⌘ (and left/right ⌥) count as the same modifier.

The gesture needs Accessibility (global monitors). Without it, it fails quietly;
Carbon `⌥Space` still works. Secure-input fields often hide global monitors too.

Settings: `settings.doubleTapModifier` = `off` | `command` | `option`. Both the
combo and the double-tap may be on at once. Fire still goes through
`HotkeyManager.onFire` → `showPicker()`.
