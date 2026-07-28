import Foundation

/// Thin wrapper over `Process`, used for the handful of jobs where shelling out
/// beats linking a library (notifications, sound, DBus queries).
enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], captureOutput: Bool = false) -> String? {
        guard let path = which(executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        if captureOutput {
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        do { try process.run() } catch { return nil }
        guard captureOutput else {
            process.waitUntilExit()
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Fire and forget, for sounds that must not block the tick.
    static func detach(_ executable: String, _ arguments: [String]) {
        guard let path = which(executable) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static var cache: [String: String?] = [:]

    static func which(_ executable: String) -> String? {
        if let cached = cache[executable] { return cached }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .split(separator: ":")
        let found = paths
            .map { "\($0)/\(executable)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        cache[executable] = found
        return found
    }

    static var isWayland: Bool {
        ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil
    }
}
