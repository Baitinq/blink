import AppKit
import BlinkCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarController()
    private var engine: BreakEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let platform = MacPlatform(status: menuBar)
        let settings = BlinkSettings(store: platform.settingsStore)
        menuBar.attach(settings: settings)
        menuBar.install()

        let engine = BreakEngine(settings: settings, platform: platform)
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
