import Foundation

public enum Phase: Equatable, Sendable {
    case working
    case warning                 // pre-break heads-up is on screen
    case resting                 // overlay is up
    case paused(until: Date?)    // nil == until the user resumes

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

/// The entire behaviour of Blink, with zero knowledge of any UI toolkit.
///
/// One tick recomputes from wall-clock deadlines rather than counting down, so
/// suspend, clock changes and a stalled run loop can never desynchronise it.
public final class BreakEngine {
    public private(set) var phase: Phase = .working
    public private(set) var secondsUntilBreak: Int = 0
    public private(set) var secondsLeftInBreak: Int = 0

    private let settings: BlinkSettings
    private let platform: Platform
    private var ticker: Cancellable?
    private var nextBreakAt: Date
    private var breakEndsAt: Date
    private var lastSnapshot: StatusSnapshot?
    /// Why a due break is being held back, if it is.
    private var heldReason: String?

    private var now: Date { platform.clock.now }

    public init(settings: BlinkSettings, platform: Platform) {
        self.settings = settings
        self.platform = platform
        self.nextBreakAt = platform.clock.now
        self.breakEndsAt = platform.clock.now
    }

    public func start() {
        platform.status.bind(commands)
        scheduleNextBreak()

        ticker = platform.scheduler.repeating(every: 0.5) { [weak self] in self?.tick() }

        // Waking must not fire a break the instant the lid opens.
        platform.systemEvents.observeWake { [weak self] in
            guard let self, !self.phase.isPaused else { return }
            self.endBreak(completed: false)
            self.scheduleNextBreak()
        }

        // Plugging or unplugging a display mid-break must not leave a screen uncovered.
        platform.systemEvents.observeDisplayChange { [weak self] in
            guard let self, case .resting = self.phase else { return }
            self.platform.overlay.relayout()
        }

        // A shorter interval should take effect now, not after the old one elapses.
        settings.onChange { [weak self] in
            guard let self else { return }
            if case .working = self.phase {
                self.nextBreakAt = min(self.nextBreakAt, self.now.addingTimeInterval(self.interval))
            }
            self.publish()
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Commands

    public var commands: BreakCommands {
        BreakCommands(
            breakNow: { [weak self] in self?.takeBreakNow() },
            skip: { [weak self] in self?.skipCurrentCycle() },
            postpone: { [weak self] in self?.postpone(minutes: self?.settings.postponeMinutes ?? 5) },
            pause: { [weak self] until in self?.pause(until: until) },
            resume: { [weak self] in self?.resume() }
        )
    }

    /// Explicitly asked for, so it also ends a pause — the user's last instruction wins.
    public func takeBreakNow() {
        if case .resting = phase { return }
        beginBreak()
    }

    public func skipCurrentCycle() {
        endBreak(completed: false)
        scheduleNextBreak()
    }

    public func postpone(minutes: Int) {
        endBreak(completed: false)
        phase = .working
        nextBreakAt = now.addingTimeInterval(Double(minutes) * 60)
        publish()
    }

    public func pause(until date: Date?) {
        endBreak(completed: false)
        platform.warningHUD.hide()
        phase = .paused(until: date)
        publish()
    }

    public func resume() {
        phase = .working
        scheduleNextBreak()
    }

    // MARK: - Loop

    private var interval: Double { Double(settings.workIntervalMinutes) * 60 }

    private func tick() {
        let now = self.now
        switch phase {
        case .paused(let until):
            if let until, now >= until { resume(); return }

        case .working, .warning:
            heldReason = settings.skipDuringMeetings ? platform.busy.busyReason(at: now) : nil
            if let heldReason {
                // A full-screen overlay during a meeting is unacceptable, so the
                // deadline is left alone: the break fires the moment you are free.
                _ = heldReason
                if phase == .warning {
                    platform.warningHUD.hide()
                    phase = .working
                }
            } else if settings.idleResetEnabled,
                      platform.idleMonitor.idleSeconds() >= Double(settings.idleRestSeconds) {
                // Away from the machine long enough to count as a rest.
                nextBreakAt = now.addingTimeInterval(interval)
                platform.warningHUD.hide()
                phase = .working
            } else if now >= nextBreakAt {
                beginBreak()
            } else {
                updateWarning(remaining: nextBreakAt.timeIntervalSince(now))
            }

        case .resting:
            if now >= breakEndsAt {
                endBreak(completed: true)
                scheduleNextBreak()
            } else {
                platform.overlay.update(secondsLeft: breakEndsAt.timeIntervalSince(now))
            }
        }
        publish()
    }

    private func updateWarning(remaining: Double) {
        let lead = Double(settings.warningLeadSeconds)
        guard settings.showPreBreakWarning, lead > 0, remaining <= lead else {
            if phase == .warning {
                phase = .working
                platform.warningHUD.hide()
            }
            return
        }
        if phase != .warning {
            phase = .warning
            platform.warningHUD.show(totalSeconds: lead)
        }
        platform.warningHUD.update(secondsLeft: Int(remaining.rounded(.up)))
    }

    private func scheduleNextBreak() {
        phase = .working
        nextBreakAt = now.addingTimeInterval(interval)
        publish()
    }

    private func beginBreak() {
        platform.warningHUD.hide()
        phase = .resting
        breakEndsAt = now.addingTimeInterval(Double(settings.breakDurationSeconds))
        platform.overlay.present(makeContext(total: Double(settings.breakDurationSeconds)))
        platform.sound.play(.breakStart)
        publish()
    }

    private func endBreak(completed: Bool) {
        guard case .resting = phase else { return }
        platform.overlay.dismiss()
        if completed {
            settings.breaksToday += 1
            platform.sound.play(.breakEnd)
        }
    }

    private func makeContext(total: Double) -> BreakContext {
        BreakContext(
            totalSeconds: total,
            prompt: Prompts.random(),
            allowsSkip: !settings.strictMode,
            fadeToBlack: settings.fadeToBlack,
            postponeMinutes: settings.postponeMinutes,
            onSkip: { [weak self] in self?.skipCurrentCycle() },
            onPostpone: { [weak self] in
                guard let self else { return }
                self.postpone(minutes: self.settings.postponeMinutes)
            }
        )
    }

    private func publish() {
        let now = self.now
        secondsUntilBreak = max(0, Int(nextBreakAt.timeIntervalSince(now).rounded()))
        secondsLeftInBreak = max(0, Int(breakEndsAt.timeIntervalSince(now).rounded(.up)))
        let snapshot = StatusSnapshot(
            phase: phase,
            secondsUntilBreak: secondsUntilBreak,
            secondsLeftInBreak: secondsLeftInBreak,
            breaksToday: settings.breaksToday,
            workIntervalMinutes: settings.workIntervalMinutes,
            breakDurationSeconds: settings.breakDurationSeconds,
            heldReason: heldReason
        )
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        platform.status.render(snapshot)
    }
}
