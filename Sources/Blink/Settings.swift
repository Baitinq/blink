import Foundation
import Combine

/// User-facing configuration, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let workInterval = "workIntervalMinutes"
        static let breakDuration = "breakDurationSeconds"
        static let warningLead = "warningLeadSeconds"
        static let strictMode = "strictMode"
        static let playSounds = "playSounds"
        static let showCountdown = "showCountdownInMenuBar"
        static let showWarning = "showPreBreakWarning"
        static let fadeToBlack = "fadeToBlack"
        static let idleReset = "idleResetEnabled"
        static let postponeMinutes = "postponeMinutes"
        static let breaksToday = "breaksToday"
        static let breaksTodayDate = "breaksTodayDate"
    }

    private let defaults = UserDefaults.standard

    init() {
        Settings.registerDefaults()
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.workInterval: 20,
            Key.breakDuration: 20,
            Key.warningLead: 10,
            Key.strictMode: false,
            Key.playSounds: true,
            Key.showCountdown: false,
            Key.showWarning: true,
            Key.fadeToBlack: true,
            Key.idleReset: true,
            Key.postponeMinutes: 5,
        ])
    }

    /// Minutes of screen time between breaks.
    @Published var workIntervalMinutes: Int = 20 {
        didSet { defaults.set(workIntervalMinutes, forKey: Key.workInterval) }
    }
    /// Seconds a break lasts.
    @Published var breakDurationSeconds: Int = 20 {
        didSet { defaults.set(breakDurationSeconds, forKey: Key.breakDuration) }
    }
    /// Seconds of heads-up before a break starts.
    @Published var warningLeadSeconds: Int = 10 {
        didSet { defaults.set(warningLeadSeconds, forKey: Key.warningLead) }
    }
    /// No skipping, no postponing.
    @Published var strictMode: Bool = false {
        didSet { defaults.set(strictMode, forKey: Key.strictMode) }
    }
    @Published var playSounds: Bool = true {
        didSet { defaults.set(playSounds, forKey: Key.playSounds) }
    }
    @Published var showCountdownInMenuBar: Bool = false {
        didSet { defaults.set(showCountdownInMenuBar, forKey: Key.showCountdown) }
    }
    @Published var showPreBreakWarning: Bool = true {
        didSet { defaults.set(showPreBreakWarning, forKey: Key.showWarning) }
    }
    /// Dim the overlay all the way down so there is nothing to look at.
    @Published var fadeToBlack: Bool = true {
        didSet { defaults.set(fadeToBlack, forKey: Key.fadeToBlack) }
    }
    /// If you were away from the keyboard long enough, that counts as a break.
    @Published var idleResetEnabled: Bool = true {
        didSet { defaults.set(idleResetEnabled, forKey: Key.idleReset) }
    }
    @Published var postponeMinutes: Int = 5 {
        didSet { defaults.set(postponeMinutes, forKey: Key.postponeMinutes) }
    }

    /// Pulls persisted values into the published properties. Called once at launch.
    func load() {
        workIntervalMinutes = defaults.integer(forKey: Key.workInterval)
        breakDurationSeconds = defaults.integer(forKey: Key.breakDuration)
        warningLeadSeconds = defaults.integer(forKey: Key.warningLead)
        strictMode = defaults.bool(forKey: Key.strictMode)
        playSounds = defaults.bool(forKey: Key.playSounds)
        showCountdownInMenuBar = defaults.bool(forKey: Key.showCountdown)
        showPreBreakWarning = defaults.bool(forKey: Key.showWarning)
        fadeToBlack = defaults.bool(forKey: Key.fadeToBlack)
        idleResetEnabled = defaults.bool(forKey: Key.idleReset)
        postponeMinutes = defaults.integer(forKey: Key.postponeMinutes)
    }

    // MARK: - Daily stats

    var breaksToday: Int {
        get {
            guard let stamp = defaults.string(forKey: Key.breaksTodayDate), stamp == Self.todayStamp else { return 0 }
            return defaults.integer(forKey: Key.breaksToday)
        }
        set {
            defaults.set(Self.todayStamp, forKey: Key.breaksTodayDate)
            defaults.set(newValue, forKey: Key.breaksToday)
        }
    }

    private static var todayStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
