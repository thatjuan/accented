import AppKit
import Carbon.HIToolbox
import Foundation

/// Optional second picker trigger: two quick taps of one modifier. Not a Carbon combo.
enum DoubleTapModifier: String, CaseIterable, Identifiable, Sendable {
    case off
    case command
    case option

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .command: return "Double-press ⌘"
        case .option: return "Double-press ⌥"
        }
    }

    var kind: DoubleTapSequencer.Kind? {
        switch self {
        case .off: return nil
        case .command: return .command
        case .option: return .option
        }
    }
}

/// Pure detector. Feed synthetic times in tests; `HotkeyManager` feeds live events.
///
/// Fire only on down→up→down→up of the watched modifier inside `window`, each
/// hold shorter than `maxHold`, with no other key or click in between.
struct DoubleTapSequencer: Equatable, Sendable {

    static let window: TimeInterval = 0.32
    static let maxHold: TimeInterval = 0.18

    enum Kind: Equatable, Sendable {
        case command
        case option
    }

    enum Result: Equatable, Sendable {
        case none
        case fire
        case reset(String)
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case down(at: TimeInterval)
        case up(firstDown: TimeInterval)
        case down2(firstDown: TimeInterval, secondDown: TimeInterval)
    }

    var watching: Kind?
    private var phase: Phase = .idle

    mutating func reset() {
        phase = .idle
    }

    /// Any non-watched key, extra modifier, or mouse click.
    mutating func noteOther() -> Result {
        guard phase != .idle else { return .none }
        phase = .idle
        return .reset("other-key")
    }

    mutating func noteFlags(kind: Kind, isDown: Bool, at time: TimeInterval) -> Result {
        guard watching == kind else { return noteOther() }
        switch (phase, isDown) {
        case (.idle, true):
            phase = .down(at: time)
            return .none
        case (.idle, false):
            return .none
        case (.down(let start), false):
            if time - start > Self.maxHold {
                phase = .idle
                return .reset("hold")
            }
            phase = .up(firstDown: start)
            return .none
        case (.down, true):
            phase = .idle
            return .reset("extra-down")
        case (.up(let start), true):
            if time - start > Self.window {
                phase = .down(at: time)
                return .reset("window")
            }
            phase = .down2(firstDown: start, secondDown: time)
            return .none
        case (.up, false):
            return .none
        case (.down2(let first, let second), false):
            if time - second > Self.maxHold {
                phase = .idle
                return .reset("hold")
            }
            if time - first > Self.window {
                phase = .idle
                return .reset("window")
            }
            phase = .idle
            return .fire
        case (.down2, true):
            phase = .idle
            return .reset("extra-down")
        }
    }

    static func kind(forKeyCode keyCode: UInt16) -> Kind? {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return .command
        case kVK_Option, kVK_RightOption: return .option
        default: return nil
        }
    }

    static func isDown(_ kind: Kind, flags: NSEvent.ModifierFlags) -> Bool {
        switch kind {
        case .command: return flags.contains(.command)
        case .option: return flags.contains(.option)
        }
    }
}
