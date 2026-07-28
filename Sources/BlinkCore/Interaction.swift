import Foundation

public enum SkipDecision: Equatable {
    /// Too early, or a stray press: nothing happens.
    case ignored
    /// Understood, but ask for confirmation before giving up the break.
    case confirm
    case act
}

/// Guards the break's escape hatches against accidents.
///
/// The overlay appears under wherever the pointer already is and swallows
/// whatever you were typing, so a single click or keystroke must never end a
/// break. Two rules, both learned from watching a real break die 2 seconds in:
///
/// 1. A grace period at the start where nothing is accepted at all.
/// 2. Deliberate intent afterwards — a held press, or a key pressed twice.
///
/// Esc in particular cannot be a one-shot: for anyone who lives in vim it is the
/// most reflexively pressed key on the board.
public struct SkipGate {
    public static let graceSeconds: TimeInterval = 1.5
    public static let confirmWindow: TimeInterval = 1.5
    public static let holdSeconds: TimeInterval = 0.6

    private let startedAt: Date
    private var confirmingSince: Date?

    public init(breakStartedAt: Date) {
        startedAt = breakStartedAt
    }

    /// True once the controls should accept input at all.
    public func isArmed(at now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= Self.graceSeconds
    }

    /// True while we are waiting for a second press to confirm.
    public func isConfirming(at now: Date) -> Bool {
        guard let confirmingSince else { return false }
        return now.timeIntervalSince(confirmingSince) < Self.confirmWindow
    }

    /// A tap of the escape hatch key: the first arms it, the second within the
    /// window commits.
    public mutating func keyPressed(at now: Date) -> SkipDecision {
        guard isArmed(at: now) else { return .ignored }
        if isConfirming(at: now) {
            confirmingSince = nil
            return .act
        }
        confirmingSince = now
        return .confirm
    }

    /// A press held for `holdSeconds` is deliberate on its own.
    public mutating func holdCompleted(at now: Date) -> SkipDecision {
        guard isArmed(at: now) else { return .ignored }
        confirmingSince = nil
        return .act
    }
}
