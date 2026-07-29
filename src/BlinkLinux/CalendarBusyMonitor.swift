import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on Linux
#endif
import BlinkCore

/// Polls a calendar's private iCal address and reports meetings in progress.
///
/// Google exposes one per calendar under Settings ▸ "Secret address in iCal
/// format"; point Blink at it with `blink set calendarICSURL <url>`. No OAuth
/// client, no tokens, and it works headless.
///
/// Caveat worth knowing: Google's secret iCal feed can lag behind the live
/// calendar by a while, so a meeting added minutes ago may not hold a break yet.
/// Recurring meetings are expanded locally, so the usual standups are covered.
final class ICSBusyMonitor: BusyMonitor {
    private let settings: BlinkSettings
    private var events: [BusyEvent] = []
    private var lastFetch = Date.distantPast
    private var fetching = false
    private let refreshInterval: TimeInterval = 300

    init(settings: BlinkSettings) {
        self.settings = settings
    }

    func busyReason(at now: Date) -> String? {
        guard settings.skipDuringMeetings, settings.calendarICSURL != nil else { return nil }
        refreshIfStale(now: now)
        guard let meeting = MeetingFilter.inProgress(events, at: now,
                                                    needAttendees: settings.meetingsNeedAttendees)
        else { return nil }
        return MeetingFilter.reason(for: meeting)
    }

    private func refreshIfStale(now: Date) {
        guard !fetching, now.timeIntervalSince(lastFetch) >= refreshInterval,
              let address = settings.calendarICSURL, let url = URL(string: address)
        else { return }
        lastFetch = now
        fetching = true

        // Off the main queue: a slow calendar server must never stall the tick.
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            let window = DateInterval(start: now.addingTimeInterval(-24 * 3600),
                                      end: now.addingTimeInterval(24 * 3600))
            let parsed = data.flatMap { String(data: $0, encoding: .utf8) }
                .map { ICS.events(from: $0, window: window) } ?? []
            DispatchQueue.main.async {
                self.events = parsed
                self.fetching = false
            }
        }.resume()
    }
}
