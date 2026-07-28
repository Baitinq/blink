import AppKit
import BlinkCore

/// The macOS `StatusDisplay`: an `NSStatusItem` plus its menu.
final class MenuBarController: NSObject, StatusDisplay, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var commands: BreakCommands?
    private var snapshot = StatusSnapshot(phase: .working, secondsUntilBreak: 0, secondsLeftInBreak: 0,
                                          breaksToday: 0, workIntervalMinutes: 20, breakDurationSeconds: 20)
    private var settings: BlinkSettings?
    private var settingsWindow: NSWindow?

    /// The settings UI is macOS-specific, so the menu owns it rather than the core.
    func attach(settings: BlinkSettings) {
        self.settings = settings
    }

    func install() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Blink — eye break reminders"
        render(snapshot)
    }

    // MARK: - StatusDisplay

    func bind(_ commands: BreakCommands) {
        self.commands = commands
    }

    func render(_ snapshot: StatusSnapshot) {
        self.snapshot = snapshot
        guard let button = statusItem.button else { return }

        let symbol: String
        switch snapshot.phase {
        case .paused: symbol = "eye.slash"
        case .resting: symbol = "eye.circle.fill"
        case .warning: symbol = "eye.trianglebadge.exclamationmark"
        case .working: symbol = "eye"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Blink")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = true

        let showCountdown = settings?.showCountdownInStatusBar ?? false
        button.title = showCountdown && !snapshot.phase.isPaused
            ? " " + Format.compact(seconds: snapshot.secondsUntilBreak)
            : ""
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header: String
        switch snapshot.phase {
        case .paused(let until):
            header = until.map { "Paused until \(Self.timeString($0))" } ?? "Paused"
        case .resting:
            header = "Break in progress"
        default:
            header = "Next break in \(Format.clock(seconds: snapshot.secondsUntilBreak))"
        }
        menu.addItem(disabled(header))
        menu.addItem(disabled("\(snapshot.breaksToday) break\(snapshot.breaksToday == 1 ? "" : "s") today  ·  every \(snapshot.workIntervalMinutes) min for \(snapshot.breakDurationSeconds)s"))
        menu.addItem(.separator())

        if snapshot.phase.isPaused {
            menu.addItem(item("Resume", #selector(resume)))
        } else {
            menu.addItem(item("Break now", #selector(breakNow)))
            menu.addItem(item("Skip this cycle", #selector(skip)))

            let pauseItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(item("for 20 minutes", #selector(pause20)))
            sub.addItem(item("for 1 hour", #selector(pause60)))
            sub.addItem(item("for 3 hours", #selector(pause180)))
            sub.addItem(item("until I resume", #selector(pauseForever)))
            pauseItem.submenu = sub
            menu.addItem(pauseItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("BlinkSettings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Blink", #selector(quit), key: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    // MARK: - Actions

    @objc private func breakNow() { commands?.breakNow() }
    @objc private func skip() { commands?.skip() }
    @objc private func resume() { commands?.resume() }
    @objc private func pause20() { commands?.pause(Date().addingTimeInterval(20 * 60)) }
    @objc private func pause60() { commands?.pause(Date().addingTimeInterval(60 * 60)) }
    @objc private func pause180() { commands?.pause(Date().addingTimeInterval(180 * 60)) }
    @objc private func pauseForever() { commands?.pause(Date?.none) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let settings, let commands else { return }
        let window = SettingsWindow.make(model: SettingsViewModel(settings: settings, commands: commands))
        window.delegate = WindowCloseWatcher.shared
        WindowCloseWatcher.shared.onClose = { [weak self] in self?.settingsWindow = nil }
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class WindowCloseWatcher: NSObject, NSWindowDelegate {
    static let shared = WindowCloseWatcher()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}
