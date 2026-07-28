import Foundation
import BlinkCore

/// `$XDG_CONFIG_HOME/blink/config.json`, written on every change. Keys match the
/// macOS `UserDefaults` keys exactly so the two ports stay comparable.
final class JSONFileStore: SettingsStore {
    private let url: URL
    private var values: [String: Any]

    init() {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: env["HOME"] ?? ".").appendingPathComponent(".config")
        let directory = base.appendingPathComponent("blink", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("config.json")

        var loaded: [String: Any] = [:]
        for (key, value) in BlinkSettings.defaults { loaded[key.rawValue] = value }
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in stored { loaded[key] = value }
        }
        values = loaded
    }

    var path: String { url.path }

    func int(_ key: SettingKey) -> Int { values[key.rawValue] as? Int ?? 0 }
    func bool(_ key: SettingKey) -> Bool { values[key.rawValue] as? Bool ?? false }
    func string(_ key: SettingKey) -> String? { values[key.rawValue] as? String }

    func set(_ value: Int, for key: SettingKey) { write(value, key) }
    func set(_ value: Bool, for key: SettingKey) { write(value, key) }
    func set(_ value: String, for key: SettingKey) { write(value, key) }

    private func write(_ value: Any, _ key: SettingKey) {
        values[key.rawValue] = value
        guard let data = try? JSONSerialization.data(withJSONObject: values,
                                                    options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
