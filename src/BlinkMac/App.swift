import AppKit
import BlinkCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: BreakEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two engines mean two overlays and breaks at twice the rate. A second
        // copy — a stray build, a double launch — bows out instead.
        let mine = ProcessInfo.processInfo.processIdentifier
        let siblings = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != mine
        }
        if !siblings.isEmpty {
            FileHandle.standardError.write(Data("blink is already running (pid \(siblings[0].processIdentifier))\n".utf8))
            NSApp.terminate(nil)
            return
        }

        let store = UserDefaultsStore()
        let settings = BlinkSettings(store: store)
        let menuBar = MenuBarController(settings: settings)
        menuBar.install()

        let engine = BreakEngine(settings: settings, platform: MacPlatform(store: store, status: menuBar))
        engine.start()
        self.engine = engine
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

@main
enum BlinkApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
