import Foundation

/// A calendar entry reduced to the few facts that decide whether a break may
/// interrupt. Platform adapters map EventKit or iCal onto this, so the decision
/// itself stays pure and testable.
public struct BusyEvent: Equatable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// The invitee declined, so it is not really happening.
    public let isDeclined: Bool
    /// Marked "free" in the calendar — a reminder, not a commitment.
    public let isTransparent: Bool
    /// Other people are invited, or there is a video link.
    public let involvesOthers: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false,
                isDeclined: Bool = false, isTransparent: Bool = false,
                involvesOthers: Bool = true) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isTransparent = isTransparent
        self.involvesOthers = involvesOthers
    }
}

public enum MeetingFilter {
    /// The meeting currently in progress, if any.
    ///
    /// All-day events are ignored on purpose: "PTO" or "Conference" covers whole
    /// days and would suppress every break. Declined and free-marked events are
    /// ignored for the same reason — they are not meetings you are sitting in.
    public static func inProgress(_ events: [BusyEvent], at now: Date,
                                  needAttendees: Bool) -> BusyEvent? {
        events
            .filter { event in
                guard !event.isAllDay, !event.isDeclined, !event.isTransparent else { return false }
                guard event.start <= now, now < event.end else { return false }
                return needAttendees ? event.involvesOthers : true
            }
            // If meetings overlap, the one ending last keeps breaks away longest.
            .max { $0.end < $1.end }
    }

    /// Short label for a status surface: "in Weekly sync".
    public static func reason(for event: BusyEvent) -> String {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "in a meeting" : "in \(title)"
    }
}
