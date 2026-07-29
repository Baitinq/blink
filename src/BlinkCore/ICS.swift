import Foundation

/// A small iCalendar reader, enough to answer "is a meeting on right now".
///
/// It lives in the core because it is pure text-in, events-out, so the self-test
/// covers it on both platforms. Linux uses it to poll a calendar's private iCal
/// address; macOS has EventKit and does not need it.
///
/// Deliberately partial: recurring events are expanded for DAILY and WEEKLY rules
/// (which is what standups and 1:1s are), with INTERVAL, BYDAY, COUNT, UNTIL and
/// EXDATE honoured. MONTHLY and YEARLY rules are ignored rather than guessed at.
public enum ICS {
    public static func events(from text: String, window: DateInterval) -> [BusyEvent] {
        unfold(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(into: (blocks: [[String]](), current: [String]?.none)) { state, line in
                let line = String(line).trimmingCharacters(in: .whitespaces)
                if line == "BEGIN:VEVENT" {
                    state.current = []
                } else if line == "END:VEVENT" {
                    if let current = state.current { state.blocks.append(current) }
                    state.current = nil
                } else if state.current != nil {
                    state.current?.append(line)
                }
            }
            .blocks
            .flatMap { occurrences(in: Fields($0), window: window) }
    }

    // MARK: - Parsing

    /// iCal folds long lines by starting continuations with a space or tab.
    private static func unfold(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
    }

    private struct Fields {
        private var values: [String: (params: String, value: String)] = [:]
        private(set) var attendeeCount = 0
        private(set) var exclusions: [Date] = []

        init(_ lines: [String]) {
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let head = String(line[line.startIndex..<colon])
                let value = String(line[line.index(after: colon)...])
                let name = head.split(separator: ";").first.map(String.init) ?? head
                let params = head.dropFirst(name.count).lowercased()

                if name == "ATTENDEE" {
                    attendeeCount += 1
                } else if name == "EXDATE" {
                    exclusions += value.split(separator: ",").compactMap {
                        ICS.date(String($0), params: params)
                    }
                } else {
                    values[name] = (params, value)
                }
            }
        }

        func string(_ name: String) -> String? { values[name]?.value }

        func date(_ name: String) -> Date? {
            guard let entry = values[name] else { return nil }
            return ICS.date(entry.value, params: entry.params)
        }

        var isAllDay: Bool { values["DTSTART"]?.params.contains("value=date") ?? false }
    }

    /// Handles "20260728T140000Z", floating local times, and all-day "20260728".
    static func date(_ raw: String, params: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
        } else if value.contains("T") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            formatter.timeZone = timeZone(from: params) ?? .current
        } else {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = timeZone(from: params) ?? .current
        }
        return formatter.date(from: value)
    }

    private static func timeZone(from params: String) -> TimeZone? {
        guard let range = params.range(of: "tzid=") else { return nil }
        let identifier = params[range.upperBound...].split(separator: ";").first.map(String.init) ?? ""
        // Params were lowercased for matching; zone ids are not.
        return TimeZone(identifier: identifier) ?? TimeZone.knownTimeZoneIdentifiers.first {
            $0.lowercased() == identifier
        }.flatMap(TimeZone.init(identifier:))
    }

    // MARK: - Expansion

    private static func occurrences(in fields: Fields, window: DateInterval) -> [BusyEvent] {
        guard let start = fields.date("DTSTART") else { return [] }
        let end = fields.date("DTEND") ?? start.addingTimeInterval(3600)
        let duration = max(0, end.timeIntervalSince(start))

        let template = BusyEvent(
            title: unescape(fields.string("SUMMARY") ?? ""),
            start: start,
            end: end,
            isAllDay: fields.isAllDay,
            isDeclined: (fields.string("STATUS") ?? "").uppercased() == "CANCELLED"
                || (fields.string("PARTSTAT") ?? "").uppercased() == "DECLINED",
            isTransparent: (fields.string("TRANSP") ?? "").uppercased() == "TRANSPARENT",
            involvesOthers: fields.attendeeCount > 1
                || hasConferenceLink(fields.string("LOCATION"), fields.string("DESCRIPTION"))
        )

        guard let rule = fields.string("RRULE") else {
            return window.intersects(DateInterval(start: start, end: max(start, end))) ? [template] : []
        }
        return expand(template, duration: duration, rule: Recurrence(rule),
                      exclusions: fields.exclusions, window: window)
    }

    private struct Recurrence {
        var frequency = ""
        var interval = 1
        var count: Int?
        var until: Date?
        var weekdays: Set<Int> = []      // 1 = Sunday, matching Calendar

        init(_ rule: String) {
            for part in rule.split(separator: ";") {
                let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                switch pair[0].uppercased() {
                case "FREQ": frequency = pair[1].uppercased()
                case "INTERVAL": interval = max(1, Int(pair[1]) ?? 1)
                case "COUNT": count = Int(pair[1])
                case "UNTIL": until = ICS.date(pair[1], params: "")
                case "BYDAY":
                    let map = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
                    weekdays = Set(pair[1].split(separator: ",").compactMap {
                        map[String($0.suffix(2)).uppercased()]
                    })
                default: break
                }
            }
        }
    }

    private static func expand(_ template: BusyEvent, duration: TimeInterval,
                               rule: Recurrence, exclusions: [Date],
                               window: DateInterval) -> [BusyEvent] {
        guard rule.frequency == "DAILY" || rule.frequency == "WEEKLY" else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        var results: [BusyEvent] = []
        var cursor = template.start
        var emitted = 0
        // One year of steps is a hard stop: a malformed rule cannot spin forever.
        for _ in 0..<400 {
            if let until = rule.until, cursor > until { break }
            if let count = rule.count, emitted >= count { break }
            if cursor > window.end { break }

            let matchesDay = rule.weekdays.isEmpty
                || rule.weekdays.contains(calendar.component(.weekday, from: cursor))
            let excluded = exclusions.contains { abs($0.timeIntervalSince(cursor)) < 60 }

            if matchesDay {
                emitted += 1
                let occurrenceEnd = cursor.addingTimeInterval(duration)
                if !excluded, window.intersects(DateInterval(start: cursor, end: max(cursor, occurrenceEnd))) {
                    results.append(BusyEvent(title: template.title, start: cursor, end: occurrenceEnd,
                                             isAllDay: template.isAllDay,
                                             isDeclined: template.isDeclined,
                                             isTransparent: template.isTransparent,
                                             involvesOthers: template.involvesOthers))
                }
            }

            let step = rule.frequency == "DAILY"
                ? DateComponents(day: rule.interval)
                : (rule.weekdays.isEmpty ? DateComponents(day: 7 * rule.interval)
                                         : DateComponents(day: 1))
            guard let next = calendar.date(byAdding: step, to: cursor) else { break }
            cursor = next
        }
        return results
    }

    private static func hasConferenceLink(_ location: String?, _ description: String?) -> Bool {
        let haystack = [location, description].compactMap { $0 }.joined(separator: " ").lowercased()
        guard !haystack.isEmpty else { return false }
        return ["meet.google.com", "zoom.us", "teams.microsoft.com", "webex.com"]
            .contains { haystack.contains($0) }
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
