@testable import Accented
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct DoubleTapTests {

    @Test
    func twoQuickTapsFire() {
        var seq = DoubleTapSequencer()
        seq.watching = .command
        _ = seq.noteFlags(kind: .command, isDown: true, at: 1.00)
        _ = seq.noteFlags(kind: .command, isDown: false, at: 1.05)
        _ = seq.noteFlags(kind: .command, isDown: true, at: 1.12)
        #expect(seq.noteFlags(kind: .command, isDown: false, at: 1.17) == .fire)
    }

    @Test
    func letterInBetweenDoesNotFire() {
        var seq = DoubleTapSequencer()
        seq.watching = .command
        _ = seq.noteFlags(kind: .command, isDown: true, at: 1.00)
        _ = seq.noteFlags(kind: .command, isDown: false, at: 1.05)
        #expect(seq.noteOther() == .reset("other-key"))
        _ = seq.noteFlags(kind: .command, isDown: true, at: 1.12)
        #expect(seq.noteFlags(kind: .command, isDown: false, at: 1.17) == .none)
    }

    @Test
    func holdDoesNotFire() {
        var seq = DoubleTapSequencer()
        seq.watching = .command
        _ = seq.noteFlags(kind: .command, isDown: true, at: 1.00)
        #expect(seq.noteFlags(kind: .command, isDown: false, at: 1.25) == .reset("hold"))
    }

    @Test
    func windowTimeoutDoesNotFire() {
        var seq = DoubleTapSequencer()
        seq.watching = .command
        _ = seq.noteFlags(kind: .command, isDown: true, at: 1.00)
        _ = seq.noteFlags(kind: .command, isDown: false, at: 1.05)
        #expect(seq.noteFlags(kind: .command, isDown: true, at: 1.50) == .reset("window"))
    }

    @Test
    func optionDoesNotCountAsCommand() {
        var seq = DoubleTapSequencer()
        seq.watching = .command
        _ = seq.noteFlags(kind: .command, isDown: true, at: 1.00)
        _ = seq.noteFlags(kind: .command, isDown: false, at: 1.05)
        #expect(seq.noteFlags(kind: .option, isDown: true, at: 1.10) == .reset("other-key"))
    }

    @Test
    func offNeverArms() {
        var seq = DoubleTapSequencer()
        seq.watching = nil
        #expect(seq.noteFlags(kind: .command, isDown: true, at: 1.00) == .none)
    }

    @Test
    func labels() {
        #expect(DoubleTapModifier.off.label == "Off")
        #expect(DoubleTapModifier.command.label.contains("⌘"))
        #expect(DoubleTapModifier.option.label.contains("⌥"))
    }
}

#else

enum DoubleTapLinkCheck {
    static let window = DoubleTapSequencer.window
}

#endif
