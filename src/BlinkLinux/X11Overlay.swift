import Foundation
import Dispatch
import BlinkCore
import CX11
import CCairo

/// The Linux break surface: one override-redirect X11 window spanning the whole
/// root, drawn with cairo, with the keyboard grabbed.
///
/// X11 rather than Wayland on purpose. Under Xorg this is exact: an
/// override-redirect window is invisible to the window manager, so nothing can
/// stack above it, and `XGrabKeyboard` swallows every keystroke the way the
/// macOS local event monitor does. Under a Wayland compositor the same code runs
/// through XWayland — the overlay still covers the screen, but the compositor
/// owns stacking and the grab only reaches XWayland clients. See docs/LINUX.md.
final class X11Overlay: BreakOverlay {
    private let display: OpaquePointer
    private let screen: Int32
    private let root: Window

    private var window: Window = 0
    private var surface: OpaquePointer?
    private var eventSource: DispatchSourceRead?

    private var context: BreakContext?
    private var secondsLeft: Double = 0
    private var skipGate = SkipGate(breakStartedAt: Date())
    private var postponeGate = SkipGate(breakStartedAt: Date())
    private var confirming: String?

    /// Fails only when there is no X display at all, which is checked at startup.
    init?() {
        guard let display = XOpenDisplay(nil) else { return nil }
        self.display = display
        screen = XDefaultScreen(display)
        root = XDefaultRootWindow(display)
    }

    // MARK: - BreakOverlay

    func present(_ context: BreakContext) {
        guard window == 0 else { return }
        self.context = context
        secondsLeft = context.totalSeconds
        skipGate = SkipGate(breakStartedAt: Date())
        postponeGate = SkipGate(breakStartedAt: Date())
        confirming = nil
        createWindow()
        draw()
    }

    func update(secondsLeft: Double) {
        self.secondsLeft = max(0, secondsLeft)
        draw()
    }

    func relayout() {
        guard window != 0 else { return }
        let size = rootSize()
        XMoveResizeWindow(display, window, 0, 0, size.width, size.height)
        cairo_xlib_surface_set_size(surface, Int32(size.width), Int32(size.height))
        XRaiseWindow(display, window)
        draw()
    }

    func dismiss() {
        guard window != 0 else { return }
        eventSource?.cancel()
        eventSource = nil
        cairo_surface_destroy(surface)
        surface = nil
        XUngrabKeyboard(display, blink_CurrentTime)
        XUngrabPointer(display, blink_CurrentTime)
        XUnmapWindow(display, window)
        XDestroyWindow(display, window)
        XFlush(display)
        window = 0
        context = nil
    }

    // MARK: - Window

    private func rootSize() -> (width: UInt32, height: UInt32) {
        var attributes = XWindowAttributes()
        XGetWindowAttributes(display, root, &attributes)
        return (UInt32(attributes.width), UInt32(attributes.height))
    }

    private func createWindow() {
        let size = rootSize()
        var attributes = XSetWindowAttributes()
        attributes.override_redirect = 1        // invisible to the window manager
        attributes.background_pixel = 0
        attributes.save_under = 1
        attributes.event_mask = blink_ExposureMask | blink_KeyPressMask
            | blink_ButtonPressMask | blink_VisibilityChangeMask
        let mask = blink_CWOverrideRedirect | blink_CWBackPixel
            | blink_CWEventMask | blink_CWSaveUnder

        window = XCreateWindow(display, root, 0, 0, size.width, size.height, 0,
                               Int32(blink_CopyFromParent), UInt32(blink_InputOutput),
                               nil, mask, &attributes)

        XMapRaised(display, window)
        XRaiseWindow(display, window)

        // Swallow input the way the macOS overlay does: keystrokes must never
        // leak into the editor behind the break.
        XGrabKeyboard(display, window, 1, Int32(blink_GrabModeAsync),
                      Int32(blink_GrabModeAsync), blink_CurrentTime)
        XGrabPointer(display, window, 1, UInt32(blink_ButtonPressMask),
                     Int32(blink_GrabModeAsync), Int32(blink_GrabModeAsync),
                     blink_None, blink_None, blink_CurrentTime)
        XFlush(display)

        surface = cairo_xlib_surface_create(display, window, XDefaultVisual(display, screen),
                                           Int32(size.width), Int32(size.height))
        startEventPump()
    }

    /// X events arrive on the connection's socket, so a read source keeps Esc
    /// responsive without polling.
    private func startEventPump() {
        let source = DispatchSource.makeReadSource(fileDescriptor: XConnectionNumber(display),
                                                  queue: .main)
        source.setEventHandler { [weak self] in self?.pumpEvents() }
        source.resume()
        eventSource = source
    }

    private func pumpEvents() {
        var event = XEvent()
        while XPending(display) > 0 {
            XNextEvent(display, &event)
            switch event.type {
            case blink_Expose:
                draw()
            case blink_VisibilityNotify:
                XRaiseWindow(display, window)   // stay on top of anything that pops up
            case blink_KeyPress:
                handleKey(&event)
            default:
                break
            }
        }
    }

    /// Esc twice skips, p twice postpones, and neither is accepted during the
    /// opening grace period — a break must not die from a reflex keystroke.
    private func handleKey(_ event: inout XEvent) {
        guard let context, context.allowsSkip else { return }
        let keysym = UInt(XLookupKeysym(&event.xkey, 0))
        let now = Date()
        switch keysym {
        case UInt(blink_XK_Escape):
            switch skipGate.pressed(at: now) {
            case .ignored: break
            case .confirm: confirming = "press esc again to skip"
            case .act: context.onSkip()
            }
        case UInt(blink_XK_p), UInt(blink_XK_P):
            switch postponeGate.pressed(at: now) {
            case .ignored: break
            case .confirm: confirming = "press p again to postpone"
            case .act: context.onPostpone()
            }
        default:
            return   // everything else is intentionally swallowed
        }
        draw()
    }

    // MARK: - Drawing

    private var progress: Double {
        BreakVisuals.progress(secondsLeft: secondsLeft, total: context?.totalSeconds ?? 0)
    }

    private var contentAlpha: Double {
        BreakVisuals.contentAlpha(progress: progress, fadeToBlack: context?.fadeToBlack ?? true)
    }

    private func draw() {
        guard window != 0, let surface, let context else { return }
        let cr = cairo_create(surface)
        defer { cairo_destroy(cr) }

        let size = rootSize()
        // X11 without a compositor has no window transparency, so the overlay
        // paints its own near-black backdrop and blends content onto it.
        cairo_set_source_rgb(cr, 0.01, 0.02, 0.02)
        cairo_paint(cr)

        for monitor in monitors(fallback: size) {
            drawPanel(cr, in: monitor, showsControls: monitor.isPrimary, context: context)
        }
        cairo_surface_flush(surface)
        XFlush(display)
    }

    private struct MonitorRect {
        let x: Double, y: Double, width: Double, height: Double
        let isPrimary: Bool
    }

    /// One panel per physical monitor, so a two-screen desk gets two countdowns.
    private func monitors(fallback size: (width: UInt32, height: UInt32)) -> [MonitorRect] {
        var count: Int32 = 0
        guard let list = XRRGetMonitors(display, root, 1, &count), count > 0 else {
            return [MonitorRect(x: 0, y: 0, width: Double(size.width),
                                height: Double(size.height), isPrimary: true)]
        }
        defer { XRRFreeMonitors(list) }
        return (0..<Int(count)).map { index in
            let info = list[index]
            return MonitorRect(x: Double(info.x), y: Double(info.y),
                               width: Double(info.width), height: Double(info.height),
                               isPrimary: info.primary != 0 || count == 1)
        }
    }

    private func drawPanel(_ cr: OpaquePointer?, in rect: MonitorRect,
                           showsControls: Bool, context: BreakContext) {
        let alpha = contentAlpha
        let centerX = rect.x + rect.width / 2
        let centerY = rect.y + rect.height / 2
        let isFinishing = secondsLeft <= BreakVisuals.finishingSeconds

        // Soft radial glow, the counterpart of the macOS RadialGradient.
        if let gradient = cairo_pattern_create_radial(centerX, centerY, 0, centerX, centerY,
                                                     min(rect.width, rect.height) * 0.55) {
            cairo_pattern_add_color_stop_rgba(gradient, 0, 0.07, 0.13, 0.16, 0.85 * alpha)
            cairo_pattern_add_color_stop_rgba(gradient, 1, 0, 0, 0, 0)
            cairo_set_source(cr, gradient)
            cairo_paint(cr)
            cairo_pattern_destroy(gradient)
        }

        let radius = 93.0
        let ringY = centerY - 110

        // Track.
        cairo_set_line_width(cr, 3)
        cairo_set_source_rgba(cr, 1, 1, 1, 0.08 * alpha)
        cairo_arc(cr, centerX, ringY, radius, 0, 2 * Double.pi)
        cairo_stroke(cr)

        // Remaining time, draining clockwise from twelve o'clock.
        let sweep = (1 - progress) * 2 * Double.pi
        if sweep > 0.001 {
            cairo_set_source_rgba(cr, 0.35, 0.85, 0.78, 0.95 * alpha)
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
            cairo_arc(cr, centerX, ringY, radius, -Double.pi / 2, -Double.pi / 2 + sweep)
            cairo_stroke(cr)
        }

        let seconds = Int(secondsLeft.rounded(.up))
        text(cr, "\(seconds)", size: 62, weight: CAIRO_FONT_WEIGHT_NORMAL,
             x: centerX, y: ringY + 20, alpha: alpha, rgb: (1, 1, 1))
        text(cr, "SECONDS", size: 12, weight: CAIRO_FONT_WEIGHT_BOLD,
             x: centerX, y: ringY + 48, alpha: 0.35 * alpha, rgb: (1, 1, 1), tracking: 3.4)

        text(cr, isFinishing ? "Welcome back" : "Look away", size: 44,
             weight: CAIRO_FONT_WEIGHT_BOLD, x: centerX, y: centerY + 40,
             alpha: 0.92 * alpha, rgb: (1, 1, 1))
        text(cr, isFinishing ? "Your eyes just got a full reset." : context.prompt,
             size: 19, weight: CAIRO_FONT_WEIGHT_NORMAL, x: centerX, y: centerY + 78,
             alpha: 0.55 * alpha, rgb: (1, 1, 1))

        guard showsControls, !isFinishing else { return }
        let hint: String
        if !context.allowsSkip {
            hint = "strict mode — this one is not skippable"
        } else if let confirming, skipGate.isConfirming(at: Date()) || postponeGate.isConfirming(at: Date()) {
            hint = confirming
        } else if skipGate.isArmed(at: Date()) {
            hint = "esc esc to skip  ·  p p to postpone \(context.postponeMinutes) min"
        } else {
            hint = ""
        }
        text(cr, hint, size: 13, weight: CAIRO_FONT_WEIGHT_NORMAL,
             x: centerX, y: rect.y + rect.height - 60, alpha: 0.3 * alpha, rgb: (1, 1, 1))
    }

    /// Centred text via cairo's toy API — enough for a handful of labels, and it
    /// keeps pango (and its dependency tree) out of the build.
    private func text(_ cr: OpaquePointer?, _ string: String, size: Double,
                      weight: cairo_font_weight_t, x: Double, y: Double,
                      alpha: Double, rgb: (Double, Double, Double), tracking: Double = 0) {
        guard alpha > 0.004 else { return }
        cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, weight)
        cairo_set_font_size(cr, size)
        cairo_set_source_rgba(cr, rgb.0, rgb.1, rgb.2, alpha)

        guard tracking == 0 else {
            var totalWidth = 0.0
            var widths: [Double] = []
            for character in string {
                var extents = cairo_text_extents_t()
                cairo_text_extents(cr, String(character), &extents)
                widths.append(extents.x_advance + tracking)
                totalWidth += extents.x_advance + tracking
            }
            var penX = x - totalWidth / 2
            for (character, advance) in zip(string, widths) {
                cairo_move_to(cr, penX, y)
                cairo_show_text(cr, String(character))
                penX += advance
            }
            return
        }

        var extents = cairo_text_extents_t()
        cairo_text_extents(cr, string, &extents)
        cairo_move_to(cr, x - extents.width / 2 - extents.x_bearing, y)
        cairo_show_text(cr, string)
    }
}
