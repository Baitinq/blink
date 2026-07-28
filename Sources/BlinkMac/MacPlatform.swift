import AppKit
import BlinkCore
import CoreGraphics

/// macOS implementation of every `BlinkCore` port.
final class MacPlatform: Platform {
    let settingsStore: SettingsStore
    let idleMonitor: IdleMonitor = QuartzIdleMonitor()
    let sound: SoundPlayer = SystemSoundPlayer()
    let overlay: BreakOverlay = MacBreakOverlay()
    let warningHUD: WarningHUD = MacWarningHUD()
    let systemEvents: SystemEvents = MacSystemEvents()
    let scheduler: Scheduler = RunLoopScheduler()
    let clock: Clock = SystemClock()
    let status: StatusDisplay

    init(store: SettingsStore, status: StatusDisplay) {
        self.settingsStore = store
        self.status = status
    }
}

// MARK: - Persistence

final class UserDefaultsStore: SettingsStore {
    private let defaults = UserDefaults.standard

    init() {
        var registration: [String: Any] = [:]
        for (key, value) in BlinkSettings.defaults { registration[key.rawValue] = value }
        defaults.register(defaults: registration)
    }

    func int(_ key: SettingKey) -> Int { defaults.integer(forKey: key.rawValue) }
    func bool(_ key: SettingKey) -> Bool { defaults.bool(forKey: key.rawValue) }
    func string(_ key: SettingKey) -> String? { defaults.string(forKey: key.rawValue) }
    func set(_ value: Int, for key: SettingKey) { defaults.set(value, forKey: key.rawValue) }
    func set(_ value: Bool, for key: SettingKey) { defaults.set(value, forKey: key.rawValue) }
    func set(_ value: String, for key: SettingKey) { defaults.set(value, forKey: key.rawValue) }
}

// MARK: - Input / power

final class QuartzIdleMonitor: IdleMonitor {
    func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                               eventType: CGEventType(rawValue: ~0)!)
    }
}

final class MacSystemEvents: SystemEvents {
    func observeWake(_ handler: @escaping () -> Void) {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        }
    }

    func observeDisplayChange(_ handler: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in handler() }
    }
}

// MARK: - Output

/// Soft audio cues so a break can be taken with your eyes off the screen entirely.
final class SystemSoundPlayer: SoundPlayer {
    func play(_ cue: SoundCue) {
        let name = cue == .breakStart ? "Submarine" : "Glass"
        NSSound(named: name)?.play()
    }
}

// MARK: - Time

/// AppKit's run loop, so ticks land on the same thread as the UI and keep
/// firing while menus are tracking.
final class RunLoopScheduler: Scheduler {
    func repeating(every seconds: Double, _ tick: @escaping () -> Void) -> BlinkCore.Cancellable {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in tick() }
        timer.tolerance = seconds * 0.4
        RunLoop.main.add(timer, forMode: .common)
        return TimerHandle(timer)
    }

    private final class TimerHandle: BlinkCore.Cancellable {
        private let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
}
