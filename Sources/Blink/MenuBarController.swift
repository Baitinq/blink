import AppKit
import Combine

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = BreakEngine.shared
    private let settings = Settings.shared
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    func install() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Blink — eye break reminders"
        refreshButton()

        engine.onChange = { [weak self] in self?.refreshButton() }
        settings.$showCountdownInMenuBar
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refreshButton() } }
            .store(in: &cancellables)
    }

    // MARK: - Button

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch engine.phase {
        case .paused: symbol = "eye.slash"
        case .resting: symbol = "eye.circle.fill"
        case .warning: symbol = "eye.trianglebadge.exclamationmark"
        case .working: symbol = "eye"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Blink")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = true

        if settings.showCountdownInMenuBar, !engine.isPaused {
            button.title = " " + Self.compact(seconds: engine.secondsUntilBreak)
        } else {
            button.title = ""
        }
    }

    private static func compact(seconds: Int) -> String {
        if seconds >= 60 { return "\(Int((Double(seconds) / 60).rounded(.up)))m" }
        return "\(seconds)s"
    }

    private static func clock(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header: String
        switch engine.phase {
        case .paused(let until):
            if let until {
                header = "Paused until \(Self.timeString(until))"
            } else {
                header = "Paused"
            }
        case .resting:
            header = "Break in progress"
        default:
            header = "Next break in \(Self.clock(seconds: engine.secondsUntilBreak))"
        }
        let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let stats = NSMenuItem(title: "\(settings.breaksToday) break\(settings.breaksToday == 1 ? "" : "s") today  ·  every \(settings.workIntervalMinutes) min for \(settings.breakDurationSeconds)s",
                               action: nil, keyEquivalent: "")
        stats.isEnabled = false
        menu.addItem(stats)
        menu.addItem(.separator())

        if engine.isPaused {
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
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Blink", #selector(quit), key: "q"))
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

    @objc private func breakNow() { engine.takeBreakNow() }
    @objc private func skip() { engine.skipCurrentCycle() }
    @objc private func resume() { engine.resume() }
    @objc private func pause20() { engine.pause(until: Date().addingTimeInterval(20 * 60)) }
    @objc private func pause60() { engine.pause(until: Date().addingTimeInterval(60 * 60)) }
    @objc private func pause180() { engine.pause(until: Date().addingTimeInterval(180 * 60)) }
    @objc private func pauseForever() { engine.pause(until: nil) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = SettingsWindow.make()
        window.delegate = WindowCloseWatcher.shared
        WindowCloseWatcher.shared.onClose = { [weak self] in self?.settingsWindow = nil }
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class WindowCloseWatcher: NSObject, NSWindowDelegate {
    static let shared = WindowCloseWatcher()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}
