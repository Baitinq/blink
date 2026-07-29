import AppKit
import EventKit
import SwiftUI
import BlinkCore

// Checks for the AppKit layer that neither the cross-platform self-test nor the
// Linux container can reach: the overlay's gate wiring and the settings window.
//
// Nothing is ever ordered on screen and the activation policy is `.prohibited`,
// so this is safe to run while you are working. Run it with:
//   packaging/macos/headless-test.sh

var failures: [String] = []
var checks = 0

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition { failures.append("\(message) (line \(line))") }
}

func group(_ name: String, _ body: () -> Void) {
    let before = failures.count
    body()
    print("  \(failures.count == before ? "✓" : "✗") \(name)")
}

/// Scratch store, so these checks never read or write real preferences.
final class ScratchStore: SettingsStore {
    private var values: [String: Any] = [:]
    init() { for (key, value) in BlinkSettings.defaults { values[key.rawValue] = value } }
    func int(_ key: SettingKey) -> Int { values[key.rawValue] as? Int ?? 0 }
    func bool(_ key: SettingKey) -> Bool { values[key.rawValue] as? Bool ?? false }
    func string(_ key: SettingKey) -> String? { values[key.rawValue] as? String }
    func set(_ value: Int, for key: SettingKey) { values[key.rawValue] = value }
    func set(_ value: Bool, for key: SettingKey) { values[key.rawValue] = value }
    func set(_ value: String, for key: SettingKey) { values[key.rawValue] = value }
}

func makeContext(onSkip: @escaping () -> Void, onPostpone: @escaping () -> Void) -> BreakContext {
    BreakContext(totalSeconds: 20, prompt: "look away", allowsSkip: true, fadeToBlack: true,
                 postponeMinutes: 5, onSkip: onSkip, onPostpone: onPostpone)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

print("BlinkMac headless test")

// MARK: - The overlay's escape hatches

group("the grace period swallows presses") {
    let state = BreakState()
    var skips = 0
    state.apply(makeContext(onSkip: { skips += 1 }, onPostpone: {}))
    state.pressSkip()
    state.pressSkip()
    expect(skips == 0, "presses during the grace period must do nothing")
    expect(!state.confirmingSkip, "and must not even prompt")
    expect(!state.armed, "controls stay dimmed")
}

// The gate is time-based, so wait it out rather than adding a test hook to it.
Thread.sleep(forTimeInterval: SkipGate.graceSeconds + 0.2)

group("one click asks, two clicks skip") {
    let state = BreakState()
    var skips = 0
    state.apply(makeContext(onSkip: { skips += 1 }, onPostpone: {}))
    Thread.sleep(forTimeInterval: SkipGate.graceSeconds + 0.1)
    state.refreshGate()
    expect(state.armed, "controls arm once the grace period has passed")

    state.pressSkip()
    expect(skips == 0, "one click must not skip — this is the bug that killed a real break")
    expect(state.confirmingSkip, "one click should ask for confirmation")

    state.pressSkip()
    expect(skips == 1, "two clicks skip")
}

group("escape and the Skip button share one gate") {
    let state = BreakState()
    var skips = 0
    state.apply(makeContext(onSkip: { skips += 1 }, onPostpone: {}))
    Thread.sleep(forTimeInterval: SkipGate.graceSeconds + 0.1)
    state.refreshGate()
    state.pressSkip()          // as if from Esc
    state.pressSkip()          // as if from the button
    expect(skips == 1, "either input can ask, either can confirm")
}

group("postpone has its own gate") {
    let state = BreakState()
    var skips = 0
    var postpones = 0
    state.apply(makeContext(onSkip: { skips += 1 }, onPostpone: { postpones += 1 }))
    Thread.sleep(forTimeInterval: SkipGate.graceSeconds + 0.1)
    state.refreshGate()

    state.pressSkip()
    state.pressPostpone()
    expect(skips == 0 && postpones == 0, "arming one hatch must not arm the other")
    expect(state.confirmingPostpone && !state.confirmingSkip, "only the last hatch prompts")

    state.pressPostpone()
    expect(postpones == 1 && skips == 0, "postpone confirmed, skip untouched")
}

group("a fresh break re-locks the gate") {
    let state = BreakState()
    var skips = 0
    state.apply(makeContext(onSkip: { skips += 1 }, onPostpone: {}))
    Thread.sleep(forTimeInterval: SkipGate.graceSeconds + 0.1)
    state.refreshGate()
    state.pressSkip()

    state.apply(makeContext(onSkip: { skips += 1 }, onPostpone: {}))
    expect(!state.armed && !state.confirmingSkip, "a new break starts locked")
    state.pressSkip()
    state.pressSkip()
    expect(skips == 0, "presses inside the new grace period do nothing")
}

group("strict mode exposes no hatches") {
    let state = BreakState()
    state.apply(BreakContext(totalSeconds: 20, prompt: "p", allowsSkip: false, fadeToBlack: true,
                             postponeMinutes: 5, onSkip: {}, onPostpone: {}))
    expect(!state.allowsSkip, "the overlay knows not to offer an exit")
}

// MARK: - Meetings

group("the calendar monitor stays silent when the feature is off") {
    let store = ScratchStore()
    let settings = BlinkSettings(store: store)
    settings.skipDuringMeetings = false
    let monitor = CalendarBusyMonitor(settings: settings)
    // Must short-circuit before touching EKEventStore: nobody who turned this
    // off should ever see a permission prompt. (Which is also why this test does
    // not exercise the enabled path — it would prompt.)
    expect(monitor.busyReason(at: Date()) == nil, "no busy reason when disabled")
}

group("settings exposes the meeting toggles") {
    let settings = BlinkSettings(store: ScratchStore())
    let model = SettingsViewModel(settings: settings,
                                 commands: BreakCommands(breakNow: {}, skip: {}, postpone: {},
                                                         pause: { _ in }, resume: {}))
    expect(model.skipDuringMeetings.wrappedValue, "on by default")
    expect(model.meetingsNeedAttendees.wrappedValue, "attendees required by default")
    model.meetingsNeedAttendees.wrappedValue = false
    expect(!settings.meetingsNeedAttendees, "toggle writes through")
}

group("a block scheduled with yourself is not a meeting") {
    // The case that matters: a personal "no interviews" hold lists you as an
    // attendee, and must not suppress breaks for its whole duration.
    expect(!CalendarBusyMonitor.involvesOthers(attendeeCount: 1, includesSelf: true,
                                               hasConferenceLink: false),
           "just me is not a meeting")
    expect(!CalendarBusyMonitor.involvesOthers(attendeeCount: 0, includesSelf: false,
                                               hasConferenceLink: false),
           "no attendees at all is not a meeting")
    expect(CalendarBusyMonitor.involvesOthers(attendeeCount: 2, includesSelf: true,
                                              hasConferenceLink: false),
           "me plus one other is a meeting")
    expect(CalendarBusyMonitor.involvesOthers(attendeeCount: 1, includesSelf: true,
                                              hasConferenceLink: true),
           "a solo invite with a video link is still a call")
}

group("your own events count as accepted") {
    let store = EKEventStore()
    let mine = EKEvent(eventStore: store)
    mine.title = "no interviews"
    mine.startDate = Date()
    mine.endDate = Date().addingTimeInterval(3600)
    // No invitee list at all: an event you put on your own calendar.
    expect(CalendarBusyMonitor.attendance(of: mine) == .accepted,
           "an event with no invitees is yours, so accepted")

    let cancelled = EKEvent(eventStore: store)
    cancelled.title = "Cancelled sync"
    cancelled.startDate = Date()
    cancelled.endDate = Date().addingTimeInterval(1800)
    // status is read-only for detached events, so this only checks the default path.
    expect(CalendarBusyMonitor.attendance(of: cancelled) == .accepted, "default is accepted")
}

group("calendar events map onto the core's busy events") {
    // EKEvents can be built in memory, so this checks the mapping — the one part
    // of the calendar path that is macOS-specific — without touching a calendar.
    let store = EKEventStore()

    let solo = EKEvent(eventStore: store)
    solo.title = "Focus time"
    solo.startDate = Date()
    solo.endDate = Date().addingTimeInterval(3600)
    let mappedSolo = CalendarBusyMonitor.busyEvent(solo)
    expect(mappedSolo.title == "Focus time", "title carried over")
    expect(!mappedSolo.involvesOthers, "a solo block involves nobody else")
    expect(!mappedSolo.isAllDay && !mappedSolo.isTransparent, "plain event")

    let call = EKEvent(eventStore: store)
    call.title = "1:1"
    call.startDate = Date()
    call.endDate = Date().addingTimeInterval(1800)
    call.notes = "Join: https://meet.google.com/abc-defg-hij"
    expect(CalendarBusyMonitor.busyEvent(call).involvesOthers,
           "a video link counts as involving others even with no attendees")

    let zoomInLocation = EKEvent(eventStore: store)
    zoomInLocation.title = "Sync"
    zoomInLocation.startDate = Date()
    zoomInLocation.endDate = Date().addingTimeInterval(1800)
    zoomInLocation.location = "https://datadoghq.zoom.us/j/123"
    expect(CalendarBusyMonitor.busyEvent(zoomInLocation).involvesOthers, "zoom link in location")

    let pto = EKEvent(eventStore: store)
    pto.title = "PTO"
    pto.startDate = Date()
    pto.endDate = Date().addingTimeInterval(86_400)
    pto.isAllDay = true
    expect(CalendarBusyMonitor.busyEvent(pto).isAllDay, "all-day flag carried over")

    // And the end-to-end decision: only the call should hold a break.
    let mapped = [solo, call, pto].map(CalendarBusyMonitor.busyEvent)
    expect(mapped.allSatisfy { $0.attendance == .accepted }, "own events map to accepted")
    let meeting = MeetingFilter.inProgress(mapped, at: Date().addingTimeInterval(60),
                                          needAttendees: true)
    expect(meeting?.title == "1:1", "the call holds the break, nothing else does")
}

// MARK: - The settings window

group("settings window builds and lays out") {
    let settings = BlinkSettings(store: ScratchStore())
    var breakNowCalls = 0
    let commands = BreakCommands(breakNow: { breakNowCalls += 1 }, skip: {}, postpone: {},
                                 pause: { _ in }, resume: {})
    let model = SettingsViewModel(settings: settings, commands: commands)
    let window = SettingsWindow.make(model: model)
    let content = window.contentView!
    content.layoutSubtreeIfNeeded()
    expect(!content.subviews.isEmpty, "the hosting view produced a view tree")
    expect(model.summary.contains("\(settings.workIntervalMinutes) minutes"),
           "the header reflects live settings")
    model.commands.breakNow()
    expect(breakNowCalls == 1, "Preview a break is wired to the engine")
    window.close()
}

group("settings controls write through to the store") {
    let store = ScratchStore()
    let settings = BlinkSettings(store: store)
    let model = SettingsViewModel(settings: settings,
                                  commands: BreakCommands(breakNow: {}, skip: {}, postpone: {},
                                                          pause: { _ in }, resume: {}))
    model.breakDurationSeconds.wrappedValue = 45
    expect(settings.breakDurationSeconds == 45, "the stepper reaches settings")
    expect(store.int(.breakDuration) == 45, "settings reach the store")

    model.strictMode.wrappedValue = true
    expect(settings.strictMode, "the toggle writes through")
    expect(store.bool(.strictMode), "and persists")
}

group("menu bar renders every phase without a status item on screen") {
    let settings = BlinkSettings(store: ScratchStore())
    let menu = MenuBarController(settings: settings)
    menu.bind(BreakCommands(breakNow: {}, skip: {}, postpone: {}, pause: { _ in }, resume: {}))
    for phase in [Phase.working, .warning, .resting, .paused(until: Date()), .paused(until: nil)] {
        menu.render(StatusSnapshot(phase: phase, secondsUntilBreak: 725, secondsLeftInBreak: 12,
                                   breaksToday: 3, workIntervalMinutes: 20, breakDurationSeconds: 20))
    }
    menu.render(StatusSnapshot(phase: .working, secondsUntilBreak: 0, secondsLeftInBreak: 0,
                               breaksToday: 3, workIntervalMinutes: 20, breakDurationSeconds: 20,
                               heldReason: "in Weekly sync"))
    expect(true, "no crash across all phases, including a held break")
}

print("")
if failures.isEmpty {
    print("\(checks) assertions — all passed")
    exit(0)
}
for failure in failures { print("FAIL  \(failure)") }
print("\n\(failures.count) failure(s)")
exit(1)
