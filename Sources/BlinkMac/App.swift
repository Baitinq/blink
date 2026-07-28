import AppKit
import BlinkCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: BreakEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
