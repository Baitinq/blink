# Blink on Linux

The Linux port is built and works. It targets **X11 directly** and relies on
XWayland under Wayland compositors — which is a deliberate trade, explained
below along with what it costs and what would remove the cost.

## What ports where

`BlinkCore` is Foundation-only and shared verbatim. Everything platform-shaped
sits behind nine small protocols in `Sources/BlinkCore/Ports.swift`:

| Port | macOS | Linux |
| --- | --- | --- |
| `SettingsStore` | `UserDefaults` | `$XDG_CONFIG_HOME/blink/config.json` |
| `IdleMonitor` | `CGEventSource.secondsSinceLastEventType` | `XScreenSaverQueryInfo` on Xorg, DBus idle monitor on Wayland |
| `SystemEvents` | `NSWorkspace.didWake`, `didChangeScreenParameters` | logind `PrepareForSleep`, XRandR topology poll |
| `SoundPlayer` | `NSSound` | `canberra-gtk-play`, else `pw-play`/`paplay` on freedesktop sounds |
| `BreakOverlay` | one `NSPanel` per screen at `.screenSaver` | one override-redirect X11 window over the whole root, cairo-drawn, one panel per XRandR monitor |
| `WarningHUD` | floating `NSPanel` + SwiftUI | `notify-send` with `x-canonical-private-synchronous` so it updates in place |
| `StatusDisplay` | `NSStatusItem` + menu | `status.json` + control FIFO + `blink` CLI |
| `Scheduler` | AppKit run loop `Timer` | `DispatchSourceTimer` on the main queue |
| `Clock` | `Date()` | `Date()` (a fake clock in tests) |

Roughly 400 shared lines, ~600 per platform.

## Why X11 rather than Wayland

1. **Override-redirect is exactly the right primitive.** Under Xorg, an
   override-redirect window is invisible to the window manager: nothing stacks
   above it, no WM policy interferes, no compositor protocol required. It is the
   closest thing Linux has to `NSWindow.level = .screenSaver`.
2. **`XGrabKeyboard` genuinely swallows input**, matching the macOS overlay's
   local event monitor, so keystrokes cannot leak into the editor behind a break.
3. **No bindings needed.** Xlib, XScreenSaver, XRandR and cairo are C APIs Swift
   imports directly through two `systemLibrary` modulemaps. No GTK, no gtk-rs, no
   generated bindings, no plugin ecosystem.
4. **Xorg is still the majority of "I stare at a screen all day" setups**, and
   XWayland covers the rest at reduced fidelity rather than not at all.

## What XWayland costs, and what Blink does about it

| Problem | Effect | Mitigation in the code |
| --- | --- | --- |
| **Idle time is wrong.** `XScreenSaverQueryInfo` under XWayland only counts input delivered to X clients, so typing in a Wayland-native window looks like idleness. | Without handling, "time away counts as a break" would cancel *every* break while you work. | `LinuxIdleMonitor` detects `WAYLAND_DISPLAY` and switches to `org.gnome.Mutter.IdleMonitor.GetIdletime`, falling back to `org.freedesktop.ScreenSaver.GetSessionIdleTime` (KDE). Sampled every 2 s and extrapolated, so no per-tick subprocess. |
| **The compositor owns stacking.** Override-redirect is a hint XWayland cannot enforce against native Wayland surfaces. | A native Wayland window *can* end up above the overlay; a workspace switch escapes it. | The overlay re-raises itself on every `VisibilityNotify`. Beyond that, strict mode is "strongly discouraging" rather than absolute — stated plainly rather than pretended away. |
| **The keyboard grab is XWayland-local.** | Esc/`p` work while the overlay has focus; a Wayland-native window that keeps focus keeps its keys. | Accepted. The control FIFO (`blink skip`) is always available as a fallback. |
| **One X screen spans all outputs.** | A single root-sized window covers every monitor, which is what we want, but the geometry is one big rectangle. | `XRRGetMonitors` splits it back into physical monitors and draws one centred panel per monitor, with controls only on the primary — same rule as macOS. |
| **No tray guarantee.** GNOME has no StatusNotifierItem without an extension. | No menu-bar equivalent. | `status.json` + FIFO + CLI, so waybar/polybar/eww can render it and scripts can drive it. A real StatusNotifierItem can be added later as a second `StatusDisplay` with no engine changes. |

## Testing it from macOS

`packaging/linux/` builds the Linux port and smoke-tests it against Xvfb, driving the
daemon through its own CLI and screenshotting the real overlay:

```sh
docker build -f packaging/linux/Dockerfile -t blink-linux .
docker run --rm -v "$PWD/out":/out blink-linux
```

That run exercises: core self-test, config writes via `blink set`, daemon
startup, `blink break`, the full 20 s break with its fade curve, break accounting,
`blink pause 1h` / `blink resume` over the FIFO, and clean SIGTERM shutdown.

## If Wayland fidelity becomes the priority

Add a third `BreakOverlay` implementation — nothing else changes:

- **gtk4-layer-shell** on the `overlay` layer with
  `gtk_layer_set_keyboard_mode(EXCLUSIVE)`. That is a genuinely un-dodgeable
  surface plus a real keyboard grab on wlroots (sway, Hyprland, river) and KDE.
  It is C, so the same modulemap approach works.
- **GNOME/Mutter** still does not expose layer-shell to clients, so it stays on
  the XWayland path. There is no way around that short of a shell extension.

Selection would be: layer-shell if `wlr-layer-shell-unstable-v1` is advertised,
else X11. The engine, settings, CLI, sounds and idle handling are untouched by
that choice — which is the point of the ports layer.

## Prior art

**SafeEyes** (Python/GTK) and **Stretchly** (Electron) already do 20-20-20 on
Linux. If you just want your eyes rested on a Linux box, either is a fine
install. Blink's reason to exist on Linux is identical behaviour to the macOS
app — same engine, same numbers, same config keys.
