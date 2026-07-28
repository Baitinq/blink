import AppKit
import SwiftUI

/// Observable state shared with the SwiftUI overlay views.
final class BreakState: ObservableObject {
    @Published var total: Double = 20
    @Published var secondsLeft: Double = 20
    @Published var prompt: String = Prompts.random()
    var progress: Double { total <= 0 ? 1 : max(0, min(1, 1 - secondsLeft / total)) }
}

enum Prompts {
    private static let all = [
        "Find something at least 6 metres away and rest your gaze there.",
        "Out the window. Far corner of the room. Anywhere but here.",
        "Let your eyes go soft and unfocused for a moment.",
        "Blink slowly a few times, then look into the distance.",
        "Roll your shoulders back and look far away.",
        "Close your eyes if you prefer — a chime will call you back.",
        "Look up. Then far. Then breathe.",
    ]
    static func random() -> String { all.randomElement()! }
}

/// A borderless window that covers one screen for the duration of a break.
private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayController {
    private var windows: [OverlayWindow] = []
    private let state = BreakState()
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    func present(total: Double) {
        guard windows.isEmpty else { return }
        state.total = total
        state.secondsLeft = total
        state.prompt = Prompts.random()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }

        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered,
                                       defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.hasShadow = false
            window.animationBehavior = .none
            window.alphaValue = 0
            let isPrimary = screen == NSScreen.main
            window.contentView = NSHostingView(
                rootView: BreakOverlayView(showsControls: isPrimary).environmentObject(state)
            )
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)

        // Fade in so the interruption is not a jump-scare.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            windows.forEach { $0.animator().alphaValue = 1 }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc skips, unless strict mode is on.
            if event.keyCode == 53 {
                if !Settings.shared.strictMode { BreakEngine.shared.skipCurrentCycle() }
                return nil
            }
            return nil   // swallow everything else so keystrokes never leak into apps
        }
    }

    func update(secondsLeft: Double) {
        state.secondsLeft = max(0, secondsLeft)
    }

    func dismiss() {
        guard !windows.isEmpty else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
        previousApp?.activate()
        previousApp = nil
    }
}
