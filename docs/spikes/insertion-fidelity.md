# Issue #2 — Caret context + text insertion fidelity

> **Status: MEASURED.** 2026-08-14, macOS 26.5.2, keyboard layout `com.apple.keylayout.Canadian`.
> Harness: signed `Accented.app` launched with `--diagnostics`, Accessibility granted.
> Raw lines: `/tmp/accented-insertion-fidelity.log` (ephemeral).

## What this gates

Issues #6 (picker panel) and #7 (insertion engine). Those issues must follow the strategies below, not invent a second architecture.

Diarc's v1 died on this class of assumption (Chromium dropping `postToPid`, silent no-ops without Accessibility). This spike measures **our** path: session-tap unicode from a background accessory app, plus AX caret reads, plus a `.nonactivatingPanel` that can become key.

## What ships (the harness)

A debug-gated Diagnostics menu inside Accented — not a standalone binary.

- `Sources/Accented/Diagnostics/DiagnosticsMenuGate.swift` — `ACCENTED_DIAGNOSTICS=1` or `--diagnostics`.
- `Sources/Accented/Diagnostics/InsertionFidelityProbe.swift` — AX snapshot, session-tap unicode insert, backspace+insert replace, AX selected-text replace, panel-key timing.
- `Sources/Accented/Diagnostics/ProbeKeyPanel.swift` — `.nonactivatingPanel` + `canBecomeKey = true` + a text-field sink.
- Wired on the **status-item** menu (accessory apps have no visible menu bar) and on `NSApp.mainMenu`.

Same reason as diarc's `PostToPidProbe`: `CGEvent` + AX need the signed bundle's persistent Accessibility grant. A `swift build` CLI would reset TCC every rebuild.

Guards: not installed unless opted in; explicit menu click only; logs before sending; aborts (and prompts) if `AXIsProcessTrusted()` is false.

Launch: `open dist/Accented.app --args --diagnostics`

## Answers

### 1. Caret reading — yes, when the focused element is a real text control

From a background accessory app, `AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute` works.

Then:

| Attribute | Result |
|---|---|
| `kAXSelectedTextRangeAttribute` | Works on AppKit text (TextEdit, Safari `<input>` / contenteditable) and Terminal. Location is the caret when length is 0. |
| `kAXValueAttribute` / `kAXStringForRangeParameterizedAttribute` | Preceding character is readable when range.location > 0. New-document caret at loc=0 has no preceding char — #7 must treat that as browse mode. |
| `kAXBoundsForRangeParameterizedAttribute` | Works in TextEdit (0×14 caret, x moves as you type) and Safari (2×13 / 2×18). **Chrome returns a 0×0 rect.** Terminal returns 0×0. Flip AX top-left → Cocoa with diarc's formula: `cocoaY = primaryHeight - ax.maxY`. |

Fail open: any missing focused element, missing range, or zero/nil bounds → browse mode and `caretRect = nil` (panel falls back to the mouse). Never block the picker.

### 2. Insertion — session-tap unicode works, layout-independent

`CGEvent` down/up with `keyboardSetUnicodeString` posted to `.cgSessionEventTap` (`.privateState` source) typed `áéîñüß¿œ` into TextEdit, Safari `<input>`, Safari contenteditable, Chrome `<input>`, Chrome contenteditable, and Terminal.

Measured on a **Canadian** layout, not US. The glyphs are attached as UTF-16, so they do not go through keycode→layout mapping. That is the point of this path versus diarc's US-keycode typing case.

Do **not** use `.postToPid`. We target the frontmost app. Diarc already recorded that Chromium mangles pid-targeted events.

Without Accessibility, `CGEvent` posting silently no-ops (same as diarc). The probe prompts and opens the Accessibility pane.

### 3. Replace — backspace + unicode, not AX

| Strategy | TextEdit | Safari `<input>` | Chrome |
|---|---|---|---|
| Synthetic backspace (`kVK_Delete` 0x33) then unicode `á` | PASS (`a` → `á`) | PASS | PASS |
| AX `kAXSelectedTextRange` + `kAXSelectedTextAttribute` | PASS | **DEGRADE** (API returns success, value stays `a`, selection becomes loc=0 len=1) | not used as primary |

**Chosen replace path:** backspace + unicode insert. Same posting stack as insert, works in the apps that accept session-tap events, including Chromium.

AX replace is a nice extra in AppKit text views and a liar in Safari. Do not make it the primary path. Do not spend a fallback tier on it in v1.

Caret must actually sit *after* the base character. A document created with `text:"a"` leaves the caret at loc=0; backspace then no-ops and insert yields `áa`. #7's context read already has the range — only replace when `location > 0`.

### 4. Focus — resign the panel first; 0 ms is enough

`.nonactivatingPanel` + `canBecomeKey = true` (the #6 contract):

| Sequence | Where `á` landed | Target field |
|---|---|---|
| Panel key, insert immediately | Panel sink (`isKey=true`) | Unchanged |
| `orderOut` then insert, 0 ms | Target (TextEdit `áx`) | Yes |
| Same, 50 ms | Target | Yes |
| Same, 100 ms | Target | Yes |

Posted session-tap events follow **key** focus, not the visually frontmost app. If the picker is key, it eats the commit.

**#6/#7 sequence:** dismiss the panel (`orderOut` / resign key), then commit on the next run-loop turn. No extra settle delay. Do not keep the panel key across the insert.

## Matrix

Legend: **PASS** = observed via AX value and/or app-level readback. **DEGRADE** = API success but wrong/no mutation, or AX too incomplete to position. **FAIL** = did not land. **n/a** = not run (unsafe or not installed). **opaque** = focused element is not a text control.

| App | Insert (session-tap unicode) | Replace (backspace+unicode) | Caret rect | Failure mode / notes |
|---|---|---|---|---|
| TextEdit | PASS | PASS | PASS (0×14, tracks caret) | New docs start at loc=0 — no preceding char until the user types. |
| Notes | PASS (once body focused) | n/a | PASS (0×23, x tracks) | Sidebar is `AXTable` and steals focus. Body is `AXTextArea` inside the third split scroll area — then preceding char + bounds work. Value is the whole note. |
| Safari `<input>` | PASS | PASS | PASS (2×13) | AX replace **DEGRADE** (success, no mutation). |
| Safari contenteditable | PASS | (same stack; not separately timed) | PASS (2×18) | Exposed as `AXTextArea`. |
| Chrome `<input>` | PASS | PASS | **0×0** — unusable | Must fall back to mouse for positioning. Insert/replace still work. |
| Chrome contenteditable | PASS | PASS | 0×0 | Same as input. First attempt against a bare `AXWebArea` (no field focus) was FAIL — focus the field. |
| VS Code / Electron | PASS | PASS | **0×0** | After editor focus: `AXTextArea`, preceding char works, insert and backspace-replace both land. Disk file may stay stale (unsaved buffer). |
| Slack | n/a (not typed into a live channel) | n/a | no | Snapshot landed on `AXButton`. Compose is Electron; treat like VS Code once the message field is focused. |
| Terminal.app | PASS | (insert-only; `cat` readback `aáéîñüß¿œ`) | 0×0 | `AXTextArea` value is the whole scrollback. Preceding char works. Bounds useless. |
| iTerm2 | n/a | n/a | n/a | Not installed. |
| Messages | n/a | n/a | n/a | Not launched; do not type into a real conversation from a spike. |
| Microsoft Word | PASS (Word API readback `Aáéîñüß¿œ`) | n/a | no | AX focused element stays `AXSplitGroup` — no range/value/bounds. Insert still lands (Word auto-caps the typed `a`). Fail open to browse + mouse. |

## Strategies for #7

**Context (`currentContext`):**

1. If Accessibility is off → browse, `caretRect = nil` (degraded mode from #5).
2. Focused element + selected range. If that fails → browse, `caretRect = nil`.
3. If range.location == 0 or preceding char is missing → browse.
4. If preceding maps to a catalog base → variants (case from the character). Else browse.
5. Caret rect from `kAXBoundsForRange` (length 0, then length 1 as fallback). If nil or `isEmpty` → `caretRect = nil` (mouse). Flip to Cocoa before handing to #6.

Budget: one focused-element copy + a couple of attribute reads. Fine for <20 ms on the apps that work.

**Insert (browse commit):**

`keyboardSetUnicodeString` + `.cgSessionEventTap` + `.privateState`. After the panel has `orderOut`'d.

**Replace (variants commit):**

One backspace (`virtualKey 0x33`) then the same unicode insert. Only when context said we have a preceding base.

**Do not ship in v1:**

- AX selected-text replace as a primary or automatic fallback (Safari lies).
- Pasteboard save / ⌘V / restore. Session-tap unicode covered every app where we had a real text focus. Adding pasteboard now is a third commit path with clipboard races and no measured customer. If #7 later finds an app that drops session-tap unicode **while focused**, add pasteboard then.
- `postToPid`.
- A settle delay after `orderOut`.

## Per-app quirks #7 should comment in the engine

- Chromium (Chrome, Electron: VS Code, likely Slack): insert/replace work once a text field/editor is focused; caret bounds are 0×0; a bare `AXWebArea` / `AXButton` focus is a miss — fail open to browse + mouse.
- Terminal: value is the whole buffer; use range + stringForRange, ignore the giant AXValue for anything except preceding-char.
- Notes: if focused role is `AXTable`, the sidebar is selected — fail open. The body `AXTextArea` (third split scroll area) is a normal text control.
- Word: insert works; AX never shows a text element. Always browse + mouse.
- Always log the commit path (`insert-unicode` / `replace-backspace`) and the focused role.

## Procedure (re-run)

1. `./Scripts/package.sh`
2. `open dist/Accented.app --args --diagnostics`
3. Grant Accessibility if prompted.
4. Focus a text field in the target app (type a character so the caret is after it).
5. Status item → Diagnostics → the case you want. Watch `/tmp/accented-insertion-fidelity.log` and the field.
