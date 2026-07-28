import Foundation
import BlinkCore
import CX11

/// Idle time, with the right backend for the session.
///
/// Under Xorg, `XScreenSaverQueryInfo` is exact and free. Under XWayland it is
/// actively wrong — it only counts input delivered to X clients, so typing in a
/// Wayland-native window looks like idleness and would silently cancel every
/// break. So on Wayland we ask the compositor over DBus instead.
final class LinuxIdleMonitor: IdleMonitor {
    private let display: OpaquePointer?
    private var info: UnsafeMutablePointer<XScreenSaverInfo>?
    private let useDBus: Bool

    private var cachedIdle: Double = 0
    private var cachedAt = Date.distantPast
    private let cacheWindow: TimeInterval = 2

    init(display: OpaquePointer?) {
        self.display = display
        useDBus = Shell.isWayland
        if !useDBus, let display {
            var eventBase: Int32 = 0
            var errorBase: Int32 = 0
            if XScreenSaverQueryExtension(display, &eventBase, &errorBase) != 0 {
                info = XScreenSaverAllocInfo()
            }
        }
    }

    var backendDescription: String {
        if useDBus { return "DBus idle monitor (Wayland session)" }
        return info != nil ? "XScreenSaver (Xorg session)" : "unavailable — idle credit disabled"
    }

    func idleSeconds() -> Double {
        if let display, let info {
            XScreenSaverQueryInfo(display, XDefaultRootWindow(display), info)
            return Double(info.pointee.idle) / 1000
        }
        guard useDBus else { return 0 }

        // Spawning gdbus twice a second would be silly; sample it occasionally
        // and extrapolate in between.
        let elapsed = Date().timeIntervalSince(cachedAt)
        if elapsed < cacheWindow { return cachedIdle + elapsed }
        cachedIdle = Self.dbusIdleSeconds() ?? 0
        cachedAt = Date()
        return cachedIdle
    }

    /// Mutter first (GNOME), then the freedesktop screensaver interface (KDE and
    /// anything else that implements it).
    private static func dbusIdleSeconds() -> Double? {
        if let output = Shell.run("gdbus", [
            "call", "--session", "--dest", "org.gnome.Mutter.IdleMonitor",
            "--object-path", "/org/gnome/Mutter/IdleMonitor/Core",
            "--method", "org.gnome.Mutter.IdleMonitor.GetIdletime",
        ], captureOutput: true), let milliseconds = firstNumber(in: output) {
            return milliseconds / 1000
        }
        if let output = Shell.run("gdbus", [
            "call", "--session", "--dest", "org.freedesktop.ScreenSaver",
            "--object-path", "/org/freedesktop/ScreenSaver",
            "--method", "org.freedesktop.ScreenSaver.GetSessionIdleTime",
        ], captureOutput: true), let seconds = firstNumber(in: output) {
            return seconds
        }
        return nil
    }

    /// gdbus prints replies as "(uint64 1234,)".
    private static func firstNumber(in output: String) -> Double? {
        let digits = output.split(whereSeparator: { !$0.isNumber })
        return digits.first.flatMap { Double($0) }
    }
}

/// Wake-from-sleep from logind, display topology by polling XRandR.
final class LinuxSystemEvents: SystemEvents {
    private let display: OpaquePointer?
    private let scheduler: Scheduler
    private var monitor: Process?
    private var poller: BlinkCore.Cancellable?
    private var lastTopology = ""

    init(display: OpaquePointer?, scheduler: Scheduler) {
        self.display = display
        self.scheduler = scheduler
    }

    /// `PrepareForSleep(false)` is logind's "we are back" signal, the analogue of
    /// NSWorkspace.didWakeNotification.
    func observeWake(_ handler: @escaping () -> Void) {
        guard let gdbus = Shell.which("gdbus") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gdbus)
        process.arguments = ["monitor", "--system", "--dest", "org.freedesktop.login1",
                            "--object-path", "/org/freedesktop/login1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let text = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard text.contains("PrepareForSleep") else { return }
            // true == going to sleep, false == just woke up
            if text.contains("false") { DispatchQueue.main.async(execute: handler) }
        }
        try? process.run()
        monitor = process
    }

    func observeDisplayChange(_ handler: @escaping () -> Void) {
        guard let display else { return }
        lastTopology = Self.topology(display)
        poller = scheduler.repeating(every: 2) { [weak self] in
            guard let self else { return }
            let current = Self.topology(display)
            guard current != self.lastTopology else { return }
            self.lastTopology = current
            handler()
        }
    }

    private static func topology(_ display: OpaquePointer) -> String {
        var count: Int32 = 0
        guard let list = XRRGetMonitors(display, XDefaultRootWindow(display), 1, &count) else {
            return "none"
        }
        defer { XRRFreeMonitors(list) }
        return (0..<Int(count))
            .map { "\(list[$0].x),\(list[$0].y),\(list[$0].width)x\(list[$0].height)" }
            .joined(separator: ";")
    }
}
