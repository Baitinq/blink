import Foundation
import Dispatch

/// Portable scheduler on the main dispatch queue. Works anywhere Dispatch does;
/// a GTK port that needs the GLib main context can swap in its own.
public final class DispatchScheduler: Scheduler {
    public init() {}

    public func repeating(every seconds: Double, _ tick: @escaping () -> Void) -> Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds, repeating: seconds, leeway: .milliseconds(200))
        timer.setEventHandler(handler: tick)
        timer.resume()
        return TimerHandle(timer)
    }

    private final class TimerHandle: Cancellable {
        private let timer: DispatchSourceTimer
        init(_ timer: DispatchSourceTimer) { self.timer = timer }
        func cancel() { timer.cancel() }
    }
}

/// Never idle. Used where the platform has no idle source available.
public final class NeverIdleMonitor: IdleMonitor {
    public init() {}
    public func idleSeconds() -> Double { 0 }
}

/// Ignores wake and display events. Used where the platform cannot report them.
public final class NoSystemEvents: SystemEvents {
    public init() {}
    public func observeWake(_ handler: @escaping () -> Void) {}
    public func observeDisplayChange(_ handler: @escaping () -> Void) {}
}

public final class SilentSoundPlayer: SoundPlayer {
    public init() {}
    public func play(_ cue: SoundCue) {}
}
