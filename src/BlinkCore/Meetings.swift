import Foundation

/// A calendar entry reduced to the few facts that decide whether a break may
/// interrupt. Platform adapters map EventKit or iCal onto this, so the decision
/// itself stays pure and testable.
/// Where you stand on an invitation. Only `accepted` means you are actually in
/// the room — being invited is not attendance, and Blink must keep working
/// through meetings you never answered.
public enum Attendance: Equatable {
    case accepted
    case tentative
    case invited
    case declined
}

public struct BusyEvent: Equatable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let attendance: Attendance
    /// Marked "free" in the calendar — a reminder, not a commitment.
    public let isTransparent: Bool
    /// Other people are invited, or there is a video link.
    public let involvesOthers: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false,
                attendance: Attendance = .accepted, isTransparent: Bool = false,
                involvesOthers: Bool = true) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.attendance = attendance
        self.isTransparent = isTransparent
        self.involvesOthers = involvesOthers
    }
}

public enum MeetingFilter {
    /// The meeting currently in progress, if any.
    ///
    /// Only accepted events count. All-day events are ignored on purpose: "PTO"
    /// or "Conference" covers whole days and would suppress every break. Invited,
    /// tentative, declined and free-marked events are ignored for the same
    /// reason — they are not meetings you are sitting in.
    public static func inProgress(_ events: [BusyEvent], at now: Date,
                                  needAttendees: Bool) -> BusyEvent? {
        events
            .filter { event in
                guard !event.isAllDay, event.attendance == .accepted, !event.isTransparent
                else { return false }
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
