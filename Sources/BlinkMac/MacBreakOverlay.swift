import AppKit
import SwiftUI
import BlinkCore

/// Observable mirror of `BreakContext` for the SwiftUI overlay views.
final class BreakState: ObservableObject {
    @Published var total: Double = 20
    @Published var secondsLeft: Double = 20
    @Published var prompt: String = ""
    @Published var allowsSkip: Bool = true
    @Published var fadeToBlack: Bool = true
    @Published var postponeMinutes: Int = 5
    var onSkip: () -> Void = {}
    var onPostpone: () -> Void = {}

    var progress: Double { total <= 0 ? 1 : max(0, min(1, 1 - secondsLeft / total)) }

    func apply(_ context: BreakContext) {
        total = context.totalSeconds
        secondsLeft = context.totalSeconds
        prompt = context.prompt
        allowsSkip = context.allowsSkip
        fadeToBlack = context.fadeToBlack
        postponeMinutes = context.postponeMinutes
        onSkip = context.onSkip
        onPostpone = context.onPostpone
    }
}

/// A borderless window that covers one screen for the duration of a break.
private final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class MacBreakOverlay: BreakOverlay {
    private var windows: [OverlayWindow] = []
    private let state = BreakState()
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    func present(_ context: BreakContext) {
        guard windows.isEmpty else { return }
        state.apply(context)
        buildWindows(fadeIn: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc skips, unless strict mode. Everything else is swallowed so
            // keystrokes never leak into the app behind the overlay.
            if event.keyCode == 53, self?.state.allowsSkip == true { self?.state.onSkip() }
            return nil
        }
    }

    func update(secondsLeft: Double) {
        state.secondsLeft = max(0, secondsLeft)
    }

    /// A display was plugged or unplugged mid-break: rebuild without re-chiming.
    func relayout() {
        guard !windows.isEmpty else { return }
        tearDownWindows(animated: false)
        buildWindows(fadeIn: false)
    }

    func dismiss() {
        guard !windows.isEmpty else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        tearDownWindows(animated: true)
        previousApp?.activate()
        previousApp = nil
    }

    // MARK: - Windows

    private func buildWindows(fadeIn: Bool) {
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
            window.alphaValue = fadeIn ? 0 : 1
            window.contentView = NSHostingView(
                rootView: BreakOverlayView(showsControls: screen == NSScreen.main).environmentObject(state)
            )
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)

        guard fadeIn else { return }
        // Fade in so the interruption is not a jump-scare.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private func tearDownWindows(animated: Bool) {
        let closing = windows
        windows = []
        guard animated else {
            closing.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
    }
}
