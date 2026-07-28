import Foundation

public enum Prompts {
    public static let all = [
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
