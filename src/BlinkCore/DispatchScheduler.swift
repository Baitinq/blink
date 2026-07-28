import Foundation
import Dispatch

/// Portable scheduler on the main dispatch queue. Works anywhere Dispatch does;
/// AppKit swaps in a run-loop timer so ticks keep firing while menus track.
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
