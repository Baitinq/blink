import AppKit
import SwiftUI
import ServiceManagement
import BlinkCore

/// Adapts the plain-Swift core `BlinkSettings` to SwiftUI's observation model, so the
/// core never has to know Combine exists.
final class SettingsViewModel: ObservableObject {
    private let settings: BlinkSettings
    private let calendar: CalendarBusyMonitor?
    let commands: BreakCommands

    init(settings: BlinkSettings, commands: BreakCommands, calendar: CalendarBusyMonitor? = nil) {
        self.settings = settings
        self.commands = commands
        self.calendar = calendar
    }

    var skipDuringMeetings: Binding<Bool> {
        Binding(
            get: { self.settings.skipDuringMeetings },
            set: { newValue in
                self.objectWillChange.send()
                self.settings.skipDuringMeetings = newValue
                // Only ever prompt for calendar access when the feature is wanted.
                if newValue { self.calendar?.requestAccessIfNeeded() }
            }
        )
    }

    var meetingsNeedAttendees: Binding<Bool> { binding(\.meetingsNeedAttendees) }

    /// Surfaces a denied Calendar permission where the toggle is, rather than
    /// silently never holding a break.
    var calendarProblem: String? { calendar?.accessProblem }

    var breaksToday: Int { settings.breaksToday }

    var workIntervalMinutes: Binding<Int> { binding(\.workIntervalMinutes) }
    var breakDurationSeconds: Binding<Int> { binding(\.breakDurationSeconds) }
    var warningLeadSeconds: Binding<Int> { binding(\.warningLeadSeconds) }
    var postponeMinutes: Binding<Int> { binding(\.postponeMinutes) }
    var strictMode: Binding<Bool> { binding(\.strictMode) }
    var playSounds: Binding<Bool> { binding(\.playSounds) }
    var fadeToBlack: Binding<Bool> { binding(\.fadeToBlack) }
    var idleResetEnabled: Binding<Bool> { binding(\.idleResetEnabled) }
    var showCountdown: Binding<Bool> { binding(\.showCountdownInStatusBar) }
    var idleRestMinutes: Binding<Int> {
        Binding(
            get: { max(1, self.settings.idleRestSeconds / 60) },
            set: { newValue in
                self.objectWillChange.send()
                self.settings.idleRestSeconds = newValue * 60
            }
        )
    }

    var summary: String {
        "Every \(settings.workIntervalMinutes) minutes, look away for \(settings.breakDurationSeconds) seconds."
    }

    private func binding<T>(_ path: ReferenceWritableKeyPath<BlinkSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: path] },
            set: { newValue in
                self.objectWillChange.send()
                self.settings[keyPath: path] = newValue
            }
        )
    }
}

enum SettingsWindow {
    static func make(model: SettingsViewModel) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Blink"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        return window
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        ScrollView {
            SettingsContent(model: model)
                .padding(28)
                .padding(.top, 6)
        }
        .frame(width: 460, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsContent: View {
    @ObservedObject var model: SettingsViewModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header

            section("Rhythm") {
                stepperRow(title: "Break every", value: model.workIntervalMinutes,
                           range: 1...120, step: 1, format: { "\($0) min" })
                Divider().opacity(0.4)
                stepperRow(title: "Break lasts", value: model.breakDurationSeconds,
                           range: 5...300, step: 5,
                           format: { $0 >= 60 ? "\($0 / 60)m \($0 % 60)s" : "\($0)s" })
                Divider().opacity(0.4)
                stepperRow(title: "Heads-up before", value: model.warningLeadSeconds,
                           range: 0...60, step: 5, format: { $0 == 0 ? "off" : "\($0)s" })
                Divider().opacity(0.4)
                stepperRow(title: "Postpone adds", value: model.postponeMinutes,
                           range: 1...30, step: 1, format: { "\($0) min" })
            }

            section("Meetings") {
                toggleRow("Hold breaks during meetings",
                          model.calendarProblem
                              ?? "Reads the calendars already in Calendar.app — including your Google account over CalDAV. A due break waits until the meeting ends.",
                          model.skipDuringMeetings)
                Divider().opacity(0.4)
                toggleRow("Only events with other people",
                          "Focus blocks and solo reminders will not hold a break; anything with attendees or a video link will.",
                          model.meetingsNeedAttendees)
            }

            section("Behaviour") {
                toggleRow("Strict mode", "No skipping and no postponing once a break starts.", model.strictMode)
                Divider().opacity(0.4)
                toggleRow("Fade the screen to black", "Mid-break the overlay dims away, so there is nothing left to look at.", model.fadeToBlack)
                Divider().opacity(0.4)
                toggleRow("Chime at start and end", "Lets you rest with your eyes shut and still know when it is over.", model.playSounds)
                Divider().opacity(0.4)
                toggleRow("Time away counts as a break",
                          "Leaving the keyboard long enough rests your eyes on its own, so the timer starts over instead of interrupting you when you sit back down.",
                          model.idleResetEnabled)
                Divider().opacity(0.4)
                stepperRow(title: "Away for at least", value: model.idleRestMinutes,
                           range: 1...30, step: 1, format: { "\($0) min" })
                Divider().opacity(0.4)
                toggleRow("Show countdown in the menu bar", "Displays minutes until the next break next to the icon.", model.showCountdown)
                Divider().opacity(0.4)
                toggleRow("Launch at login", loginError ?? "Start Blink automatically when you log in.", Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        loginError = LoginItem.set(newValue)
                    }
                ))
            }

            HStack {
                Button("Preview a break") { model.commands.breakNow() }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Text("\(model.breaksToday) breaks today")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "eye")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color(red: 0.25, green: 0.7, blue: 0.66))
            VStack(alignment: .leading, spacing: 2) {
                Text("Blink").font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(model.summary)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 11) { content() }
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
        }
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int,
                            format: @escaping (Int) -> String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, design: .rounded))
            Spacer()
            Text(format(value.wrappedValue))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// Launch at login. `SMAppService` reports `notFound` until the app registers
/// once, which is not an error — only a failed `register()` is.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error string to surface in the UI, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Could not update launch at login: \(error.localizedDescription)"
        }
    }
}
