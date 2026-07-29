import Foundation
import BlinkCore
import CX11

/// Linux implementation of every `BlinkCore` port, X11-first.
final class LinuxPlatform: Platform {
    let settingsStore: SettingsStore
    let idleMonitor: IdleMonitor
    let sound: SoundPlayer
    let overlay: BreakOverlay
    let warningHUD: WarningHUD
    let systemEvents: SystemEvents
    let busy: BusyMonitor
    let status: StatusDisplay
    let scheduler: Scheduler = DispatchScheduler()
    let clock: Clock = SystemClock()

    let describeIdleBackend: String

    /// Fails when there is no X display, which is the one thing this port cannot
    /// work around.
    init?(verbose: Bool, store: SettingsStore) {
        guard let x11 = X11Overlay() else { return nil }
        let display = XOpenDisplay(nil)   // separate connection for queries
        let idle = LinuxIdleMonitor(display: display)

        settingsStore = store
        // No calendar source on Linux: macOS gets meeting awareness from
        // Calendar.app, and there is no equally credential-free equivalent here.
        busy = NeverBusy()
        idleMonitor = idle
        describeIdleBackend = idle.backendDescription
        sound = LinuxSoundPlayer()
        overlay = x11
        warningHUD = NotifyWarningHUD()
        status = ControlSurface(verbose: verbose)
        systemEvents = LinuxSystemEvents(display: display, scheduler: scheduler)
    }
}
