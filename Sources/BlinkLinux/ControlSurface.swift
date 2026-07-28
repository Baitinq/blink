import Foundation
import Dispatch
import BlinkCore

/// Blink's Linux status surface and remote control.
///
/// There is no dependable tray on every Linux desktop (GNOME needs an extension
/// for StatusNotifierItem), so instead of pretending, the daemon publishes state
/// to a file and takes commands on a FIFO. `blink status`, `blink pause 1h` and
/// friends talk to it, and a tray or a Waybar/polybar module can read the same
/// JSON. A StatusNotifierItem implementation can be dropped in later as a second
/// StatusDisplay without the engine noticing.
final class ControlSurface: StatusDisplay {
    static var runtimeDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_RUNTIME_DIR"] ?? "/tmp"
        return URL(fileURLWithPath: base).appendingPathComponent("blink", isDirectory: true)
    }

    static var statusPath: URL { runtimeDirectory.appendingPathComponent("status.json") }
    static var controlPath: URL { runtimeDirectory.appendingPathComponent("control") }

    private var commands: BreakCommands?
    private var readSource: DispatchSourceRead?
    private var fifoDescriptor: Int32 = -1
    private let verbose: Bool
    private var lastPrinted: String?

    init(verbose: Bool) {
        self.verbose = verbose
        try? FileManager.default.createDirectory(at: Self.runtimeDirectory, withIntermediateDirectories: true)
    }

    // MARK: - StatusDisplay

    func bind(_ commands: BreakCommands) {
        self.commands = commands
        openControlFIFO()
    }

    func render(_ snapshot: StatusSnapshot) {
        let payload: [String: Any] = [
            "phase": Self.phaseName(snapshot.phase),
            "text": Self.summary(snapshot),
            "secondsUntilBreak": snapshot.secondsUntilBreak,
            "secondsLeftInBreak": snapshot.secondsLeftInBreak,
            "breaksToday": snapshot.breaksToday,
            "workIntervalMinutes": snapshot.workIntervalMinutes,
            "breakDurationSeconds": snapshot.breakDurationSeconds,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            try? data.write(to: Self.statusPath, options: .atomic)
        }

        guard verbose else { return }
        let line = Self.summary(snapshot)
        guard line != lastPrinted else { return }
        lastPrinted = line
        print(line)
    }

    static func summary(_ snapshot: StatusSnapshot) -> String {
        switch snapshot.phase {
        case .paused(let until):
            guard let until else { return "paused" }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "paused until \(formatter.string(from: until))"
        case .resting:
            return "break — \(snapshot.secondsLeftInBreak)s left"
        case .warning:
            return "break in \(snapshot.secondsUntilBreak)s"
        case .working:
            return "next break in \(Format.clock(seconds: snapshot.secondsUntilBreak))  ·  \(snapshot.breaksToday) today"
        }
    }

    private static func phaseName(_ phase: Phase) -> String {
        switch phase {
        case .working: return "working"
        case .warning: return "warning"
        case .resting: return "resting"
        case .paused: return "paused"
        }
    }

    // MARK: - Control FIFO

    private func openControlFIFO() {
        let path = Self.controlPath.path
        if !FileManager.default.fileExists(atPath: path) {
            mkfifo(path, 0o600)
        }
        // O_RDWR keeps the pipe open across clients, so the read source never
        // sees a permanent EOF.
        fifoDescriptor = open(path, O_RDWR | O_NONBLOCK)
        guard fifoDescriptor >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: fifoDescriptor, queue: .main)
        source.setEventHandler { [weak self] in self?.readCommands() }
        source.resume()
        readSource = source
    }

    private func readCommands() {
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = read(fifoDescriptor, &buffer, buffer.count)
        guard count > 0, let text = String(bytes: buffer[0..<count], encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            handle(String(line).trimmingCharacters(in: .whitespaces))
        }
    }

    private func handle(_ line: String) {
        guard let commands, !line.isEmpty else { return }
        let parts = line.split(separator: " ").map(String.init)
        switch parts[0] {
        case "break": commands.breakNow()
        case "skip": commands.skip()
        case "postpone": commands.postpone()
        case "resume": commands.resume()
        case "pause":
            let argument = parts.count > 1 ? parts[1] : "inf"
            if let deadline = PauseDuration(argument).deadline(from: Date()) {
                commands.pause(deadline)
            }
        case "quit": exit(0)
        default: break
        }
    }

    // MARK: - Client side

    static func send(_ command: String) -> Bool {
        let descriptor = open(controlPath.path, O_WRONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        let line = command + "\n"
        return write(descriptor, line, line.utf8.count) > 0
    }

    static func readStatus() -> String? {
        guard let data = try? Data(contentsOf: statusPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["text"] as? String
    }
}
