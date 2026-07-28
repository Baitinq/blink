import Foundation

extension SettingKey {
    public static let workInterval = SettingKey("workIntervalMinutes")
    public static let breakDuration = SettingKey("breakDurationSeconds")
    public static let warningLead = SettingKey("warningLeadSeconds")
    public static let postponeMinutes = SettingKey("postponeMinutes")
    public static let strictMode = SettingKey("strictMode")
    public static let playSounds = SettingKey("playSounds")
    public static let showCountdown = SettingKey("showCountdownInMenuBar")
    public static let showWarning = SettingKey("showPreBreakWarning")
    public static let fadeToBlack = SettingKey("fadeToBlack")
    public static let idleReset = SettingKey("idleResetEnabled")
    public static let breaksToday = SettingKey("breaksToday")
    public static let breaksTodayDate = SettingKey("breaksTodayDate")
}

/// Configuration and daily stats. Values live in the platform's store, so there
/// is exactly one source of truth and no load/save dance.
public final class BlinkSettings {
    public static let defaults: [SettingKey: Any] = [
        .workInterval: 20,
        .breakDuration: 20,
        .warningLead: 10,
        .postponeMinutes: 5,
        .strictMode: false,
        .playSounds: true,
        .showCountdown: false,
        .showWarning: true,
        .fadeToBlack: true,
        .idleReset: true,
    ]

    private let store: SettingsStore

    private var observers: [() -> Void] = []

    public init(store: SettingsStore) {
        self.store = store
    }

    /// Notified whenever any setting changes, so the engine can re-arm and a UI
    /// can redraw. Additive, so one subsystem cannot silently displace another.
    public func onChange(_ handler: @escaping () -> Void) {
        observers.append(handler)
    }

    private func notify() {
        observers.forEach { $0() }
    }

    // MARK: Rhythm

    public var workIntervalMinutes: Int {
        get { store.int(.workInterval) }
        set { write(newValue, .workInterval) }
    }
    public var breakDurationSeconds: Int {
        get { store.int(.breakDuration) }
        set { write(newValue, .breakDuration) }
    }
    public var warningLeadSeconds: Int {
        get { store.int(.warningLead) }
        set { write(newValue, .warningLead) }
    }
    public var postponeMinutes: Int {
        get { store.int(.postponeMinutes) }
        set { write(newValue, .postponeMinutes) }
    }

    // MARK: Behaviour

    public var strictMode: Bool {
        get { store.bool(.strictMode) }
        set { write(newValue, .strictMode) }
    }
    public var playSounds: Bool {
        get { store.bool(.playSounds) }
        set { write(newValue, .playSounds) }
    }
    public var showCountdownInStatusBar: Bool {
        get { store.bool(.showCountdown) }
        set { write(newValue, .showCountdown) }
    }
    public var showPreBreakWarning: Bool {
        get { store.bool(.showWarning) }
        set { write(newValue, .showWarning) }
    }
    public var fadeToBlack: Bool {
        get { store.bool(.fadeToBlack) }
        set { write(newValue, .fadeToBlack) }
    }
    public var idleResetEnabled: Bool {
        get { store.bool(.idleReset) }
        set { write(newValue, .idleReset) }
    }

    // MARK: Daily stats

    /// Resets itself when the calendar day rolls over.
    public var breaksToday: Int {
        get {
            guard store.string(.breaksTodayDate) == Self.todayStamp else { return 0 }
            return store.int(.breaksToday)
        }
        set {
            store.set(Self.todayStamp, for: .breaksTodayDate)
            store.set(newValue, for: .breaksToday)
            notify()
        }
    }

    private static var todayStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func write(_ value: Int, _ key: SettingKey) {
        store.set(value, for: key)
        notify()
    }

    private func write(_ value: Bool, _ key: SettingKey) {
        store.set(value, for: key)
        notify()
    }
}
