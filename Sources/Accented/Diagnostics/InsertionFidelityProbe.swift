import AppKit
import ApplicationServices
import CoreGraphics
import os

/// **Diagnostic harness (NOT a product feature).** Measures caret reading + character
/// insertion/replacement against the frontmost app — the two make-or-break mechanisms issue #7
/// will ship. Results land in `docs/spikes/insertion-fidelity.md`.
///
/// ## Why it lives in the app, not a CLI
/// `CGEvent` posting and AX reads need Accessibility (TCC) trust. The signed `Accented.app`
/// carries a stable Developer ID grant that persists across rebuilds; a bare `swift build`
/// binary's grant resets per rebuild and often attaches to the launching terminal. Same reason
/// diarc's `PostToPidProbe` lives in-app.
///
/// ## Safety
/// Every mutating case posts **real** events to the frontmost app. Nothing runs on launch:
/// each case fires only from an explicit Diagnostics menu click. Cases log (os.Logger,
/// category `InsertionFidelity`) what they are about to do *before* doing it, and append a
/// structured line to `/tmp/accented-insertion-fidelity.log`.
///
/// ## Posting
/// Unicode insert uses `keyboardSetUnicodeString` posted to `.cgSessionEventTap` (NOT
/// `.postToPid`) — we target whichever app is frontmost. Event source is `.privateState`.
///
/// ## Concurrency
/// `@MainActor`. AX + AppKit + CGEvent posting stay on the main thread so key-down → key-up
/// ordering is deterministic.
@MainActor
final class InsertionFidelityProbe {

    private let logger = Logger(subsystem: "com.thatjuan.accented", category: "InsertionFidelity")
    private let reportURL = URL(fileURLWithPath: "/tmp/accented-insertion-fidelity.log")
    private let panel = ProbeKeyPanel()

    /// Characters issue #2 asked us to type, regardless of the active keyboard layout.
    static let probeGlyphs = "áéîñüß¿œ"

    private enum Timing {
        static let keyStrokeGapUs: useconds_t = 12_000
        static let settleMs: UInt64 = 80
    }

    enum Case: Int, CaseIterable {
        case snapshotCaret = 1
        case insertUnicode
        case replaceBackspaceInsert
        case replaceAX
        case panelInsertWhileKey
        case panelResignInsert0
        case panelResignInsert50
        case panelResignInsert100
        case runFrontmostSuite

        var title: String {
            switch self {
            case .snapshotCaret: return "1. Snapshot caret (AX read)"
            case .insertUnicode: return "2. Insert unicode via session tap"
            case .replaceBackspaceInsert: return "3. Replace: backspace + unicode"
            case .replaceAX: return "4. Replace: AX selected-text"
            case .panelInsertWhileKey: return "5. Panel key, then insert"
            case .panelResignInsert0: return "6. Panel resign, insert (0ms)"
            case .panelResignInsert50: return "7. Panel resign, insert (50ms)"
            case .panelResignInsert100: return "8. Panel resign, insert (100ms)"
            case .runFrontmostSuite: return "9. Run suite against frontmost"
            }
        }
    }

    func run(_ probeCase: Case) {
        if !AXIsProcessTrusted() {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            if !trusted {
                logger.error("Accessibility NOT granted — prompted. Enable Accented in System Settings, then re-run.")
                report("ABORT not-trusted case=\(probeCase.rawValue)")
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
                return
            }
        }

        let front = NSWorkspace.shared.frontmostApplication
        let frontName = front?.localizedName ?? "?"
        let frontBundle = front?.bundleIdentifier ?? "?"
        logger.notice("▶︎ \(probeCase.title, privacy: .public) → frontmost \(frontName, privacy: .public) (\(frontBundle, privacy: .public))")
        report("BEGIN case=\(probeCase.rawValue) title=\(probeCase.title) front=\(frontName) bundle=\(frontBundle)")

        switch probeCase {
        case .snapshotCaret:
            logSnapshot(tag: "snapshot")
        case .insertUnicode:
            runInsertUnicode()
        case .replaceBackspaceInsert:
            runReplaceBackspaceInsert()
        case .replaceAX:
            runReplaceAX()
        case .panelInsertWhileKey:
            runPanelInsert(resignFirst: false, delayMs: 0)
        case .panelResignInsert0:
            runPanelInsert(resignFirst: true, delayMs: 0)
        case .panelResignInsert50:
            runPanelInsert(resignFirst: true, delayMs: 50)
        case .panelResignInsert100:
            runPanelInsert(resignFirst: true, delayMs: 100)
        case .runFrontmostSuite:
            runFrontmostSuite()
        }
    }

    // MARK: - Cases

    private func runInsertUnicode() {
        let before = snapshot()
        logSnapshot(tag: "before-insert", snap: before)
        logger.notice("Inserting \"\(Self.probeGlyphs, privacy: .public)\" via keyboardSetUnicodeString → .cgSessionEventTap")
        postUnicodeString(Self.probeGlyphs)
        settleThen { [weak self] in
            guard let self else { return }
            let after = self.snapshot()
            self.logSnapshot(tag: "after-insert", snap: after)
            self.reportVerdict(op: "insert-unicode", before: before, after: after, expectedContains: Self.probeGlyphs)
        }
    }

    private func runReplaceBackspaceInsert() {
        let before = snapshot()
        logSnapshot(tag: "before-bs-replace", snap: before)
        logger.notice("Replace via backspace + unicode \"á\"")
        postKey(0x33, flags: []) // kVK_Delete (backward delete)
        postUnicodeString("á")
        settleThen { [weak self] in
            guard let self else { return }
            let after = self.snapshot()
            self.logSnapshot(tag: "after-bs-replace", snap: after)
            self.reportVerdict(op: "replace-backspace", before: before, after: after, expectedContains: "á")
        }
    }

    private func runReplaceAX() {
        let before = snapshot()
        logSnapshot(tag: "before-ax-replace", snap: before)
        guard let element = before.element else {
            logger.error("AX replace: no focused element. Aborting.")
            report("VERDICT op=replace-ax result=FAIL reason=no-focused-element")
            return
        }
        guard let range = before.selectedRange, range.location > 0 else {
            logger.error("AX replace: caret not after a character (range=\(String(describing: before.selectedRange), privacy: .public)). Aborting.")
            report("VERDICT op=replace-ax result=FAIL reason=no-preceding-char")
            return
        }
        var select = CFRange(location: range.location - 1, length: 1)
        guard let axRange = AXValueCreate(.cfRange, &select) else {
            report("VERDICT op=replace-ax result=FAIL reason=axvalue-create")
            return
        }
        let setRange = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        let setText = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "á" as CFString)
        logger.notice("AX replace: set range loc=\(range.location - 1, privacy: .public) err=\(setRange.rawValue, privacy: .public); set text err=\(setText.rawValue, privacy: .public)")
        settleThen { [weak self] in
            guard let self else { return }
            let after = self.snapshot()
            self.logSnapshot(tag: "after-ax-replace", snap: after)
            let rangeOK = setRange == .success
            let textOK = setText == .success
            let landed = after.value?.contains("á") == true
            let result: String
            if rangeOK && textOK && landed {
                result = "PASS"
            } else if rangeOK && textOK {
                result = "DEGRADE"
            } else {
                result = "FAIL"
            }
            self.report("VERDICT op=replace-ax result=\(result) setRange=\(setRange.rawValue) setText=\(setText.rawValue) landed=\(landed)")
        }
    }

    private func runPanelInsert(resignFirst: Bool, delayMs: Int) {
        let before = snapshot()
        logSnapshot(tag: "before-panel", snap: before)
        panel.resetSink()
        // Park the panel away from the caret so we can still see the target field.
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.minX + 40, y: f.maxY - 140))
        }
        panel.makeKeyAndOrderFront(nil)
        logger.notice("Panel ordered front (nonactivating, canBecomeKey=true); isKey=\(self.panel.isKeyWindow, privacy: .public)")

        let fire = { [weak self] in
            guard let self else { return }
            if resignFirst {
                self.panel.orderOut(nil)
                self.logger.notice("Panel ordered out; delay \(delayMs, privacy: .public)ms then insert")
            } else {
                self.panel.sink.becomeFirstResponder()
                self.logger.notice("Panel kept key (sink first responder); inserting")
            }
            let post = {
                self.postUnicodeString("á")
                self.settleThen {
                    let after = self.snapshot()
                    self.logSnapshot(tag: "after-panel", snap: after)
                    let sink = self.panel.sink.stringValue
                    self.report("PANEL resign=\(resignFirst) delayMs=\(delayMs) sink=\"\(sink)\" isKey=\(self.panel.isKeyWindow)")
                    self.reportVerdict(op: "panel-insert-\(resignFirst ? "resign" : "key")-\(delayMs)", before: before, after: after, expectedContains: "á")
                    if !resignFirst {
                        self.panel.orderOut(nil)
                    }
                }
            }
            if delayMs == 0 {
                post()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
                    post()
                }
            }
        }

        // Give the panel a run-loop turn to actually become key before we decide.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
            fire()
        }
    }

    private func runFrontmostSuite() {
        let before = snapshot()
        logSnapshot(tag: "suite-before", snap: before)
        postUnicodeString("á")
        settleThen { [weak self] in
            guard let self else { return }
            let afterInsert = self.snapshot()
            self.logSnapshot(tag: "suite-after-insert", snap: afterInsert)
            self.reportVerdict(op: "suite-insert", before: before, after: afterInsert, expectedContains: "á")

            // Only attempt AX replace when we have a preceding character to target.
            if let range = afterInsert.selectedRange, range.location > 0, afterInsert.element != nil {
                var select = CFRange(location: range.location - 1, length: 1)
                if let axRange = AXValueCreate(.cfRange, &select), let element = afterInsert.element {
                    _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
                    let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "é" as CFString)
                    self.settleThen {
                        let afterAX = self.snapshot()
                        self.logSnapshot(tag: "suite-after-ax", snap: afterAX)
                        self.report("VERDICT op=suite-ax-replace axErr=\(err.rawValue) landed=\(afterAX.value?.contains("é") == true)")
                    }
                }
            } else {
                self.report("VERDICT op=suite-ax-replace result=SKIP reason=no-preceding-or-no-element")
            }
        }
    }

    // MARK: - Snapshot

    struct CaretSnapshot {
        var role: String?
        var subrole: String?
        var selectedRange: CFRange?
        var value: String?
        var preceding: String?
        var axBounds: CGRect?
        var cocoaBounds: CGRect?
        var element: AXUIElement?
        var error: String?
    }

    private func snapshot() -> CaretSnapshot {
        var snap = CaretSnapshot()
        let systemWide = AXUIElementCreateSystemWide()
        guard let focused = copyAttribute(systemWide, kAXFocusedUIElementAttribute as String) else {
            snap.error = "no-focused-element"
            return snap
        }
        // AXUIElement is a CFType; the copy comes back as CFTypeRef.
        let element = focused as! AXUIElement
        snap.element = element
        snap.role = copyString(element, kAXRoleAttribute as String)
        snap.subrole = copyString(element, kAXSubroleAttribute as String)
        snap.value = copyString(element, kAXValueAttribute as String)
        snap.selectedRange = copyRange(element, kAXSelectedTextRangeAttribute as String)

        if let range = snap.selectedRange, range.location > 0 {
            var one = CFRange(location: range.location - 1, length: 1)
            if let axRange = AXValueCreate(.cfRange, &one) {
                snap.preceding = copyParameterizedString(element, kAXStringForRangeParameterizedAttribute as String, axRange)
                if snap.preceding == nil, let value = snap.value {
                    let idx = value.index(value.startIndex, offsetBy: min(range.location - 1, value.count - 1))
                    if idx < value.endIndex {
                        snap.preceding = String(value[idx])
                    }
                }
            }
        }

        if let range = snap.selectedRange {
            // Zero-length caret first; some apps want length 1.
            var caret = CFRange(location: range.location, length: 0)
            if let axRange = AXValueCreate(.cfRange, &caret) {
                snap.axBounds = copyParameterizedRect(element, kAXBoundsForRangeParameterizedAttribute as String, axRange)
            }
            if snap.axBounds == nil || snap.axBounds == .zero {
                var one = CFRange(location: max(range.location - 1, 0), length: 1)
                if let axRange = AXValueCreate(.cfRange, &one) {
                    snap.axBounds = copyParameterizedRect(element, kAXBoundsForRangeParameterizedAttribute as String, axRange)
                }
            }
            if let ax = snap.axBounds {
                snap.cocoaBounds = cocoaRect(fromAX: ax)
            }
        }
        return snap
    }

    private func logSnapshot(tag: String, snap: CaretSnapshot? = nil) {
        let snap = snap ?? snapshot()
        let rangeDesc: String
        if let r = snap.selectedRange {
            rangeDesc = "loc=\(r.location) len=\(r.length)"
        } else {
            rangeDesc = "nil"
        }
        let valuePreview = truncated(snap.value, limit: 80)
        let line = """
        SNAP \(tag) role=\(snap.role ?? "nil") subrole=\(snap.subrole ?? "nil") \
        range={\(rangeDesc)} preceding=\(snap.preceding ?? "nil") \
        axBounds=\(rectDesc(snap.axBounds)) cocoaBounds=\(rectDesc(snap.cocoaBounds)) \
        value=\(valuePreview) err=\(snap.error ?? "none")
        """
        logger.notice("\(line, privacy: .public)")
        report(line)
    }

    private func reportVerdict(op: String, before: CaretSnapshot, after: CaretSnapshot, expectedContains: String) {
        let beforeVal = before.value ?? ""
        let afterVal = after.value ?? ""
        let axReadable = after.value != nil || before.value != nil
        let landed: Bool
        if axReadable {
            landed = afterVal.contains(expectedContains) && afterVal != beforeVal
        } else {
            landed = false
        }
        let result: String
        if after.error == "no-focused-element" && before.error == "no-focused-element" {
            result = "UNKNOWN-NO-AX"
        } else if landed {
            result = "PASS"
        } else if !axReadable {
            result = "UNKNOWN-NO-VALUE"
        } else {
            result = "FAIL"
        }
        let line = "VERDICT op=\(op) result=\(result) axReadable=\(axReadable) beforeLen=\(beforeVal.count) afterLen=\(afterVal.count)"
        logger.notice("\(line, privacy: .public)")
        report(line)
    }

    // MARK: - Event synthesis

    /// Inject a Unicode string on a key-down/up pair and post to the session tap (frontmost app).
    /// Port of diarc `PostToPidProbe.postUnicodeString`, retargeted from `postToPid` to
    /// `.cgSessionEventTap` as issue #2 specifies.
    func postUnicodeString(_ string: String) {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            logger.error("Failed to create Unicode key event")
            return
        }
        let utf16 = Array(string.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cgSessionEventTap)
        usleep(Timing.keyStrokeGapUs)
        up.post(tap: .cgSessionEventTap)
        usleep(Timing.keyStrokeGapUs)
    }

    /// Post a key down/up for a virtual keycode (used for backspace). Session tap, not postToPid.
    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            logger.error("Failed to create key event for keycode \(keyCode, privacy: .public)")
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        usleep(Timing.keyStrokeGapUs)
        up.post(tap: .cgSessionEventTap)
        usleep(Timing.keyStrokeGapUs)
    }

    // MARK: - AX helpers

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return err == .success ? value : nil
    }

    private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private func copyRange(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let raw = copyAttribute(element, attribute) else { return nil }
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let ax = raw as! AXValue
        var range = CFRange()
        guard AXValueGetValue(ax, .cfRange, &range) else { return nil }
        return range
    }

    private func copyParameterizedString(_ element: AXUIElement, _ attribute: String, _ parameter: AXValue) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        return err == .success ? value as? String : nil
    }

    private func copyParameterizedRect(_ element: AXUIElement, _ attribute: String, _ parameter: AXValue) -> CGRect? {
        var value: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        guard err == .success, let raw = value, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let ax = raw as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(ax, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Flip an AX top-left-origin rect into Cocoa bottom-left space. Same formula as diarc
    /// `SwitcherWindowController.cocoaFrame` (primary display height − AX maxY).
    private func cocoaRect(fromAX ax: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? ax.maxY
        let cocoaY = primaryHeight - ax.maxY
        return CGRect(x: ax.origin.x, y: cocoaY, width: ax.width, height: ax.height)
    }

    // MARK: - Reporting

    private func settleThen(_ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(Timing.settleMs))) {
            body()
        }
    }

    private func report(_ line: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let data = stamped.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: reportURL.path) {
                if let handle = try? FileHandle(forWritingTo: reportURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: reportURL)
            }
        }
    }

    private func truncated(_ value: String?, limit: Int) -> String {
        guard let value else { return "nil" }
        let compact = value.replacingOccurrences(of: "\n", with: "\\n")
        if compact.count <= limit { return "\"\(compact)\"" }
        return "\"\(compact.prefix(limit))…\"(len=\(compact.count))"
    }

    private func rectDesc(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(format: "{%.1f,%.1f %.1f×%.1f}", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
}
