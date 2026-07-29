import AppKit
import EventKit
import BlinkCore

/// Reads whatever calendars are already configured in Calendar.app — which is
/// how a Google account gets here, over CalDAV — and reports when a meeting is
/// in progress so a break can be held back.
///
/// EventKit rather than the Google Calendar API on purpose: no OAuth client, no
/// tokens to refresh, no credentials on disk, and it covers every account you
/// add later for free. macOS keeps it synced.
final class CalendarBusyMonitor: BusyMonitor {
    private let store = EKEventStore()
    private let settings: BlinkSettings

    private var events: [BusyEvent] = []
    private var lastFetch = Date.distantPast
    private var access: Access = .unknown

    private enum Access {
        case unknown, granted, denied
    }

    /// Calendars change rarely; a due break can wait a few seconds for the truth.
    private let refreshInterval: TimeInterval = 30

    init(settings: BlinkSettings) {
        self.settings = settings
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.lastFetch = .distantPast
        }
    }

    /// Asks for calendar access. Only called when the feature is switched on, so
    /// nobody who does not want it ever sees the prompt.
    func requestAccessIfNeeded() {
        guard access == .unknown else { return }
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.lastFetch = .distantPast
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    // MARK: - BusyMonitor

    func busyReason(at now: Date) -> String? {
        guard settings.skipDuringMeetings else { return nil }
        refreshIfStale(now: now)
        guard let meeting = MeetingFilter.inProgress(events, at: now,
                                                    needAttendees: settings.meetingsNeedAttendees)
        else { return nil }
        return MeetingFilter.reason(for: meeting)
    }

    /// Nil when everything is fine, otherwise something to show in Settings.
    var accessProblem: String? {
        switch Self.authorization {
        case .denied, .restricted:
            return "Calendar access was denied — enable Blink in System Settings ▸ Privacy & Security ▸ Calendars."
        default:
            return nil
        }
    }

    private static var authorization: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Fetching

    private func refreshIfStale(now: Date) {
        guard now.timeIntervalSince(lastFetch) >= refreshInterval else { return }
        lastFetch = now

        switch Self.authorization {
        case .notDetermined:
            requestAccessIfNeeded()
            return
        case .denied, .restricted:
            events = []
            return
        default:
            break
        }

        // A window around now is enough: we only ever ask "is a meeting on right
        // now", and this keeps the query cheap.
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600),
                                                 end: now.addingTimeInterval(6 * 3600),
                                                 calendars: nil)
        events = store.events(matching: predicate).map(Self.busyEvent)
    }

    private static func busyEvent(_ event: EKEvent) -> BusyEvent {
        BusyEvent(
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isDeclined: declined(event),
            isTransparent: event.availability == .free,
            involvesOthers: event.hasAttendees || hasConferenceLink(event)
        )
    }

    private static func declined(_ event: EKEvent) -> Bool {
        if event.status == .canceled { return true }
        // The organiser's copy of your own decline shows up as a participant status.
        return event.attendees?.contains {
            $0.isCurrentUser && $0.participantStatus == .declined
        } ?? false
    }

    /// A solo event with a Meet or Zoom link is still a call.
    private static func hasConferenceLink(_ event: EKEvent) -> Bool {
        let haystack = [event.url?.absoluteString, event.notes, event.location]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        guard !haystack.isEmpty else { return false }
        return ["meet.google.com", "zoom.us", "teams.microsoft.com", "webex.com", "whereby.com"]
            .contains { haystack.contains($0) }
    }
}
