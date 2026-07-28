import AppKit
import Combine
import CoreGraphics

enum Phase: Equatable {
    case working
    case warning      // pre-break heads-up is on screen
    case resting      // overlay is up
    case paused(until: Date?)   // nil == indefinitely
}

/// Drives the whole work/break cycle. Single 0.5s tick keeps every timer honest
/// across sleep, wake and display changes.
final class BreakEngine: ObservableObject {
    static let shared = BreakEngine()

    @Published private(set) var phase: Phase = .working
    /// Seconds until the next break starts (only meaningful while working/warning).
    @Published private(set) var secondsUntilBreak: Int = 0
    /// Seconds left in the current break.
    @Published private(set) var secondsLeftInBreak: Int = 0

    private let settings = Settings.shared
    private var ticker: Timer?
    private var nextBreakAt = Date()
    private var breakEndsAt = Date()
    private var overlay = OverlayController()
    private var warningPanel = WarningPanelController()
    private var cancellables = Set<AnyCancellable>()

    var onChange: (() -> Void)?

    private init() {}

    func start() {
        scheduleNextBreak()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        ticker?.tolerance = 0.2
        RunLoop.main.add(ticker!, forMode: .common)

        // Re-arm after sleep so we do not fire a break the instant the lid opens.
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleWake()
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleWake()
        }

        // Plugging or unplugging a display mid-break must not leave a screen uncovered.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, case .resting = self.phase else { return }
            self.overlay.dismiss()
            self.overlay.present(total: self.breakEndsAt.timeIntervalSinceNow)
        }

        // Interval edits should take effect immediately.
        settings.$workIntervalMinutes
            .dropFirst()
            .sink { [weak self] minutes in
                guard let self, case .working = self.phase else { return }
                self.nextBreakAt = min(self.nextBreakAt, Date().addingTimeInterval(Double(minutes) * 60))
                self.tick()
            }
            .store(in: &cancellables)
    }

    // MARK: - Commands

    func takeBreakNow() {
        if case .resting = phase { return }
        beginBreak()
    }

    func skipCurrentCycle() {
        endBreak(completed: false)
        scheduleNextBreak()
    }

    func postpone(minutes: Int) {
        endBreak(completed: false)
        phase = .working
        nextBreakAt = Date().addingTimeInterval(Double(minutes) * 60)
        publish()
    }

    func pause(until date: Date?) {
        endBreak(completed: false)
        warningPanel.hide()
        phase = .paused(until: date)
        publish()
    }

    func resume() {
        phase = .working
        scheduleNextBreak()
    }

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    // MARK: - Loop

    private func tick() {
        let now = Date()
        switch phase {
        case .paused(let until):
            if let until, now >= until { resume(); return }

        case .working, .warning:
            if settings.idleResetEnabled, idleSeconds() >= Double(settings.breakDurationSeconds) {
                // Away from the machine long enough that the eyes already rested.
                nextBreakAt = now.addingTimeInterval(Double(settings.workIntervalMinutes) * 60)
                warningPanel.hide()
                phase = .working
            } else if now >= nextBreakAt {
                beginBreak()
            } else {
                let remaining = nextBreakAt.timeIntervalSince(now)
                let lead = Double(settings.warningLeadSeconds)
                if settings.showPreBreakWarning, lead > 0, remaining <= lead {
                    if phase != .warning {
                        phase = .warning
                        warningPanel.show(totalSeconds: lead)
                    }
                    warningPanel.update(secondsLeft: Int(remaining.rounded(.up)))
                } else if phase == .warning {
                    phase = .working
                    warningPanel.hide()
                }
            }

        case .resting:
            if now >= breakEndsAt {
                endBreak(completed: true)
                scheduleNextBreak()
            } else {
                overlay.update(secondsLeft: breakEndsAt.timeIntervalSince(now))
            }
        }
        publish()
    }

    private func publish() {
        let now = Date()
        secondsUntilBreak = max(0, Int(nextBreakAt.timeIntervalSince(now).rounded()))
        secondsLeftInBreak = max(0, Int(breakEndsAt.timeIntervalSince(now).rounded(.up)))
        onChange?()
    }

    private func scheduleNextBreak() {
        phase = .working
        nextBreakAt = Date().addingTimeInterval(Double(settings.workIntervalMinutes) * 60)
        publish()
    }

    private func handleWake() {
        guard !isPaused else { return }
        endBreak(completed: false)
        scheduleNextBreak()
    }

    private func beginBreak() {
        warningPanel.hide()
        phase = .resting
        breakEndsAt = Date().addingTimeInterval(Double(settings.breakDurationSeconds))
        overlay.present(total: Double(settings.breakDurationSeconds))
        Chime.play(.start)
        publish()
    }

    private func endBreak(completed: Bool) {
        guard case .resting = phase else { return }
        overlay.dismiss()
        if completed {
            settings.breaksToday += 1
            Chime.play(.end)
        }
    }

    // MARK: - Idle

    private func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }
}

/// Soft audio cues so a break can be taken with your eyes off the screen entirely.
enum Chime {
    enum Kind { case start, end }

    static func play(_ kind: Kind) {
        guard Settings.shared.playSounds else { return }
        let name = kind == .start ? "Submarine" : "Glass"
        NSSound(named: name)?.play()
    }
}
