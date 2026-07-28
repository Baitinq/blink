import Foundation

public enum Prompts {
    private static let all = [
        "Find something at least 6 metres away and rest your gaze there.",
        "Out the window. Far corner of the room. Anywhere but here.",
        "Let your eyes go soft and unfocused for a moment.",
        "Blink slowly a few times, then look into the distance.",
        "Roll your shoulders back and look far away.",
        "Close your eyes if you prefer — a chime will call you back.",
        "Look up. Then far. Then breathe.",
    ]

    public static func random() -> String { all.randomElement()! }
}

public enum Format {
    /// "12:05" — for a status surface with room to spare.
    public static func clock(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "13m" / "45s" — for a cramped tray label.
    public static func compact(seconds: Int) -> String {
        seconds >= 60 ? "\(Int((Double(seconds) / 60).rounded(.up)))m" : "\(seconds)s"
    }
}

/// Rules the break overlay follows on every platform, so AppKit and cairo cannot
/// drift apart. Both renderers ask these functions rather than reimplementing them.
public enum BreakVisuals {
    /// Seconds of "Welcome back" before the overlay disappears.
    public static let finishingSeconds: Double = 3

    /// Opacity of the overlay's content over the course of a break: fully visible
    /// at both ends, almost invisible through the middle. The dip is the point —
    /// nothing worth looking at means eyes actually leave the screen.
    public static func contentAlpha(progress: Double, fadeToBlack: Bool) -> Double {
        guard fadeToBlack else { return 1 }
        let dipStart = 0.18
        let dipEnd = 0.82
        let ramp = 0.12
        guard progress >= dipStart, progress <= dipEnd else { return 1 }
        let fadeIn = min(1, (progress - dipStart) / ramp)
        let fadeOut = min(1, (dipEnd - progress) / ramp)
        return 1 - 0.88 * min(fadeIn, fadeOut)
    }

    public static func progress(secondsLeft: Double, total: Double) -> Double {
        guard total > 0 else { return 1 }
        return max(0, min(1, 1 - secondsLeft / total))
    }
}

/// Grammar for pause requests: "20m", "1h", "90s", "inf".
public enum PauseDuration: Equatable {
    case seconds(TimeInterval)
    case indefinite
    /// Rejected rather than quietly treated as "pause forever".
    case invalid

    public init(_ text: String) {
        if text == "inf" || text == "forever" {
            self = .indefinite
            return
        }
        guard let value = Double(text.filter({ $0.isNumber || $0 == "." })), value > 0 else {
            self = .invalid
            return
        }
        switch text.last {
        case "h": self = .seconds(value * 3600)
        case "m": self = .seconds(value * 60)
        case "s": self = .seconds(value)
        default: self = .invalid
        }
    }

    /// Absolute deadline to hand to `BreakEngine.pause(until:)`, or nil for indefinite.
    public func deadline(from now: Date) -> Date?? {
        switch self {
        case .indefinite: return .some(nil)
        case .seconds(let seconds): return now.addingTimeInterval(seconds)
        case .invalid: return nil
        }
    }
}
