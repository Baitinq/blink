import AppKit
import EventKit
import ServiceManagement
import BlinkCore

/// `Blink --calendar-check` and `Blink --login-item` — the two things that cannot
/// be verified from a test binary, because both depend on this app's own code
/// identity (calendar permission is granted to the bundle, and a login item
/// registers the calling bundle).
enum Diagnostics {
    /// Also written to a file, because these have to be launched with `open -a`:
    /// macOS attributes a permission request to the *responsible* process, so a
    /// binary started from a shell is judged as the terminal, not as Blink, and
    /// would always report "not yet asked".
    static let logPath = "/tmp/blink-diagnostics.txt"
    private static var transcript = ""

    private static func say(_ line: String) {
        print(line)
        transcript += line + "\n"
    }

    private static func finish(_ code: Int32) -> Never {
        try? transcript.write(toFile: logPath, atomically: true, encoding: .utf8)
        exit(code)
    }

    static func run(_ argument: String) -> Never {
        switch argument {
        case "--calendar-check": calendarCheck()
        case "--login-item": loginItem(CommandLine.arguments.dropFirst(2).first)
        default:
            say("""
            Blink runs in the menu bar; there is nothing to do on the command line except:
              --calendar-check          what Blink can see in your calendar right now
              --login-item [on|off]     launch at login: report, enable or disable

            Launch these with `open -a Blink --args <flag>` and read \(logPath),
            so macOS judges the request as Blink rather than as your terminal.
            """)
            finish(argument == "--help" ? 0 : 1)
        }
    }

    private static func calendarCheck() -> Never {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .event)
        say("calendar access: \(describe(status))")
        guard status.rawValue == 3 else { finish(1) }

        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600),
                                                 end: now.addingTimeInterval(6 * 3600),
                                                 calendars: nil)
        let events = store.events(matching: predicate)
        say("calendars: \(store.calendars(for: .event).count)")
        say("events in the surrounding 12 hours: \(events.count)")

        let settings = BlinkSettings(store: UserDefaultsStore())
        let mapped = events.map(CalendarBusyMonitor.busyEvent)
        let meeting = MeetingFilter.inProgress(mapped, at: now,
                                              needAttendees: settings.meetingsNeedAttendees)
        say("right now: \(meeting.map(MeetingFilter.reason) ?? "not in a meeting — breaks will fire")")

        // Show the reasoning for anything overlapping now, so a surprise is explainable.
        let overlapping = mapped.filter { $0.start <= now && now < $0.end }
        if !overlapping.isEmpty {
            say("\noverlapping events and why they do or do not hold a break:")
            for event in overlapping {
                var reasons: [String] = []
                if event.isAllDay { reasons.append("all-day") }
                if event.attendance != .accepted { reasons.append("\(event.attendance)") }
                if event.isTransparent { reasons.append("marked free") }
                if !event.involvesOthers { reasons.append("nobody else involved") }
                let verdict = reasons.isEmpty ? "HOLDS breaks" : "ignored (\(reasons.joined(separator: ", ")))"
                say("  \(event.title.isEmpty ? "(untitled)" : event.title) — \(verdict)")
            }
        }
        finish(0)
    }

    private static func loginItem(_ action: String?) -> Never {
        switch action {
        case "on":
            let problem = LoginItem.set(true)
            say(problem ?? "launch at login: enabled")
            finish(problem == nil ? 0 : 1)
        case "off":
            let problem = LoginItem.set(false)
            say(problem ?? "launch at login: disabled")
            finish(problem == nil ? 0 : 1)
        default:
            say("launch at login: \(LoginItem.isEnabled ? "enabled" : "off")")
            say("SMAppService reports: \(describe(SMAppService.mainApp.status))")
            finish(0)
        }
    }

    private static func describe(_ status: EKAuthorizationStatus) -> String {
        switch status.rawValue {
        case 0: return "not yet asked"
        case 1: return "restricted"
        case 2: return "denied — enable Blink in System Settings ▸ Privacy & Security ▸ Calendars"
        case 3: return "granted (full)"
        case 4: return "granted (write-only, not enough to see meetings)"
        default: return "unknown (\(status.rawValue))"
        }
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "not registered"
        case .notFound: return "not found — macOS cannot see this bundle"
        case .requiresApproval: return "waiting for your approval in System Settings ▸ General ▸ Login Items"
        @unknown default: return "unknown"
        }
    }
}
