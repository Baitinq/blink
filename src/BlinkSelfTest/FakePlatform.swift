import Foundation
import BlinkCore

/// In-memory store, so tests never touch the real user's config.
final class MemoryStore: SettingsStore {
    var values: [String: Any] = [:]

    init() {
        for (key, value) in BlinkSettings.defaults { values[key.rawValue] = value }
    }

    func int(_ key: SettingKey) -> Int { values[key.rawValue] as? Int ?? 0 }
    func bool(_ key: SettingKey) -> Bool { values[key.rawValue] as? Bool ?? false }
    func string(_ key: SettingKey) -> String? { values[key.rawValue] as? String }
    func set(_ value: Int, for key: SettingKey) { values[key.rawValue] = value }
    func set(_ value: Bool, for key: SettingKey) { values[key.rawValue] = value }
    func set(_ value: String, for key: SettingKey) { values[key.rawValue] = value }
}

final class FakeClock: Clock {
    var now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { now = start }
    func advance(_ seconds: Double) { now = now.addingTimeInterval(seconds) }
}

/// Captures the engine's tick so tests can drive time by hand.
final class ManualScheduler: Scheduler {
    private(set) var tick: (() -> Void)?
    private(set) var interval: Double = 0
    private(set) var cancelled = false

    func repeating(every seconds: Double, _ tick: @escaping () -> Void) -> BlinkCore.Cancellable {
        interval = seconds
        self.tick = tick
        return Handle { [weak self] in self?.cancelled = true }
    }

    private final class Handle: BlinkCore.Cancellable {
        private let onCancel: () -> Void
        init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
        func cancel() { onCancel() }
    }
}

final class FakeIdleMonitor: IdleMonitor {
    var idle: Double = 0
    func idleSeconds() -> Double { idle }
}

final class RecordingSound: SoundPlayer {
    var cues: [SoundCue] = []
    func play(_ cue: SoundCue) { cues.append(cue) }
}

final class RecordingOverlay: BreakOverlay {
    var presentCount = 0
    var dismissCount = 0
    var relayoutCount = 0
    var isVisible = false
    var lastSecondsLeft: Double?
    var context: BreakContext?

    func present(_ context: BreakContext) {
        presentCount += 1
        isVisible = true
        self.context = context
    }
    func update(secondsLeft: Double) { lastSecondsLeft = secondsLeft }
    func relayout() { relayoutCount += 1 }
    func dismiss() {
        dismissCount += 1
        isVisible = false
    }
}

final class RecordingHUD: WarningHUD {
    var isVisible = false
    var showCount = 0
    var lastSecondsLeft: Int?

    func show(totalSeconds: Double) {
        showCount += 1
        isVisible = true
    }
    func update(secondsLeft: Int) { lastSecondsLeft = secondsLeft }
    func hide() { isVisible = false }
}

final class ManualSystemEvents: SystemEvents {
    private var wakeHandlers: [() -> Void] = []
    private var displayHandlers: [() -> Void] = []

    func observeWake(_ handler: @escaping () -> Void) { wakeHandlers.append(handler) }
    func observeDisplayChange(_ handler: @escaping () -> Void) { displayHandlers.append(handler) }
    func fireWake() { wakeHandlers.forEach { $0() } }
    func fireDisplayChange() { displayHandlers.forEach { $0() } }
}

/// Reports whatever the test tells it to.
final class FakeBusyMonitor: BusyMonitor {
    var reason: String?
    func busyReason(at now: Date) -> String? { reason }
}

final class RecordingStatus: StatusDisplay {
    var snapshots: [StatusSnapshot] = []
    var commands: BreakCommands?

    func bind(_ commands: BreakCommands) { self.commands = commands }
    func render(_ snapshot: StatusSnapshot) { snapshots.append(snapshot) }
}

final class FakePlatform: Platform {
    let settingsStore: SettingsStore = MemoryStore()
    let fakeIdle = FakeIdleMonitor()
    let recordingSound = RecordingSound()
    let recordingOverlay = RecordingOverlay()
    let recordingHUD = RecordingHUD()
    let manualEvents = ManualSystemEvents()
    let recordingStatus = RecordingStatus()
    let manualScheduler = ManualScheduler()
    let fakeClock = FakeClock()
    let fakeBusy = FakeBusyMonitor()

    var idleMonitor: IdleMonitor { fakeIdle }
    var sound: SoundPlayer { recordingSound }
    var overlay: BreakOverlay { recordingOverlay }
    var warningHUD: WarningHUD { recordingHUD }
    var systemEvents: SystemEvents { manualEvents }
    var busy: BusyMonitor { fakeBusy }
    var status: StatusDisplay { recordingStatus }
    var scheduler: Scheduler { manualScheduler }
    var clock: Clock { fakeClock }

    /// Advance time and run the engine tick, the way the real run loop would.
    func advance(_ seconds: Double, step: Double = 0.5) {
        var remaining = seconds
        while remaining > 0 {
            let delta = min(step, remaining)
            fakeClock.advance(delta)
            manualScheduler.tick?()
            remaining -= delta
        }
    }
}
