import Foundation

/// Everything Blink needs from an operating system, and nothing more.
///
/// `BlinkCore` imports Foundation only — no AppKit, no SwiftUI, no Combine, no
/// GTK. A platform is a bundle of small adapters implementing these ports.
public protocol Platform: AnyObject {
    var settingsStore: SettingsStore { get }
    var idleMonitor: IdleMonitor { get }
    var sound: SoundPlayer { get }
    var overlay: BreakOverlay { get }
    var warningHUD: WarningHUD { get }
    var systemEvents: SystemEvents { get }
    var busy: BusyMonitor { get }
    var status: StatusDisplay { get }
    var scheduler: Scheduler { get }
    var clock: Clock { get }
}

// MARK: - Persistence

/// Key/value persistence. macOS backs this with `UserDefaults`, Linux with a
/// JSON file under `$XDG_CONFIG_HOME/blink`.
public protocol SettingsStore: AnyObject {
    func int(_ key: SettingKey) -> Int
    func bool(_ key: SettingKey) -> Bool
    func string(_ key: SettingKey) -> String?
    func set(_ value: Int, for key: SettingKey)
    func set(_ value: Bool, for key: SettingKey)
    func set(_ value: String, for key: SettingKey)
}

public struct SettingKey: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Input / power

/// Seconds since the last keyboard or pointer event anywhere in the session.
public protocol IdleMonitor: AnyObject {
    func idleSeconds() -> Double
}

/// Wake-from-sleep and display-topology changes. Both need the engine to react,
/// and both exist on every desktop OS under a different name.
public protocol SystemEvents: AnyObject {
    func observeWake(_ handler: @escaping () -> Void)
    func observeDisplayChange(_ handler: @escaping () -> Void)
}

/// Times when a full-screen overlay would be unacceptable — a meeting, a call.
/// macOS reads the calendars already configured in Calendar.app; Linux polls an
/// iCal URL.
public protocol BusyMonitor: AnyObject {
    /// Nil when free, otherwise a short reason to show in the status surface.
    func busyReason(at now: Date) -> String?
}

/// Used when nothing can report busy-ness, and as the default on both platforms
/// until a calendar is available.
public final class NeverBusy: BusyMonitor {
    public init() {}
    public func busyReason(at now: Date) -> String? { nil }
}

// MARK: - Output

public enum SoundCue: Sendable {
    case breakStart
    case breakEnd
}

public protocol SoundPlayer: AnyObject {
    func play(_ cue: SoundCue)
}

/// Everything the overlay needs to draw a break, plus the two ways out of it.
/// Passing the escape hatches as closures keeps the core free of any UI concept.
public struct BreakContext {
    public let totalSeconds: Double
    public let prompt: String
    public let allowsSkip: Bool
    public let fadeToBlack: Bool
    public let postponeMinutes: Int
    public let onSkip: () -> Void
    public let onPostpone: () -> Void

    public init(totalSeconds: Double, prompt: String, allowsSkip: Bool, fadeToBlack: Bool,
                postponeMinutes: Int, onSkip: @escaping () -> Void, onPostpone: @escaping () -> Void) {
        self.totalSeconds = totalSeconds
        self.prompt = prompt
        self.allowsSkip = allowsSkip
        self.fadeToBlack = fadeToBlack
        self.postponeMinutes = postponeMinutes
        self.onSkip = onSkip
        self.onPostpone = onPostpone
    }
}

/// The full-screen break surface: `.screenSaver` NSPanels on macOS,
/// layer-shell surfaces on Wayland.
public protocol BreakOverlay: AnyObject {
    func present(_ context: BreakContext)
    func update(secondsLeft: Double)
    /// Rebuild for a changed display topology while a break is running.
    func relayout()
    func dismiss()
}

/// The small pre-break heads-up surface.
public protocol WarningHUD: AnyObject {
    func show(totalSeconds: Double)
    func update(secondsLeft: Int)
    func hide()
}

// MARK: - Status surface

public struct StatusSnapshot: Equatable {
    public let phase: Phase
    public let secondsUntilBreak: Int
    public let secondsLeftInBreak: Int
    public let breaksToday: Int
    public let workIntervalMinutes: Int
    public let breakDurationSeconds: Int
    /// Set while a due break is being held back, e.g. "in a meeting".
    public let heldReason: String?

    public init(phase: Phase, secondsUntilBreak: Int, secondsLeftInBreak: Int, breaksToday: Int,
                workIntervalMinutes: Int, breakDurationSeconds: Int, heldReason: String? = nil) {
        self.phase = phase
        self.secondsUntilBreak = secondsUntilBreak
        self.secondsLeftInBreak = secondsLeftInBreak
        self.breaksToday = breaksToday
        self.workIntervalMinutes = workIntervalMinutes
        self.breakDurationSeconds = breakDurationSeconds
        self.heldReason = heldReason
    }
}

/// Commands a status surface (menu bar item, tray icon, CLI) can issue.
public struct BreakCommands {
    public let breakNow: () -> Void
    public let skip: () -> Void
    public let postpone: () -> Void
    public let pause: (Date?) -> Void
    public let resume: () -> Void

    public init(breakNow: @escaping () -> Void, skip: @escaping () -> Void,
                postpone: @escaping () -> Void, pause: @escaping (Date?) -> Void,
                resume: @escaping () -> Void) {
        self.breakNow = breakNow
        self.skip = skip
        self.postpone = postpone
        self.pause = pause
        self.resume = resume
    }
}

public protocol StatusDisplay: AnyObject {
    func bind(_ commands: BreakCommands)
    func render(_ snapshot: StatusSnapshot)
}

// MARK: - Time

public protocol Cancellable: AnyObject {
    func cancel()
}

/// A repeating tick on the platform's UI thread. macOS uses the AppKit run loop,
/// a GTK port would use `g_timeout_add`.
public protocol Scheduler: AnyObject {
    func repeating(every seconds: Double, _ tick: @escaping () -> Void) -> Cancellable
}

/// Injectable "now", so the engine's deadline arithmetic is testable without
/// waiting in real time.
public protocol Clock: AnyObject {
    var now: Date { get }
}

public final class SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}
