# Porting Blink to Linux

Yes, there is a path. But almost none of the *code* ports — only the design does.
The macOS app is ~900 lines, of which roughly 300 are pure logic (state machine,
settings, stats) and 600 are AppKit/SwiftUI. Linux has no AppKit and no SwiftUI,
so the honest plan is a sibling implementation that keeps the same UX contract.

## What Blink actually needs from an OS

| Capability | macOS today | Linux equivalent |
| --- | --- | --- |
| Tray/menu-bar item | `NSStatusItem` | StatusNotifierItem over DBus (`ksni` / libayatana-appindicator). Works on KDE, XFCE, Cinnamon; GNOME needs the AppIndicator extension |
| Un-dodgeable full-screen overlay per display | `NSPanel` at `.screenSaver` level | `wlr-layer-shell` (`overlay` layer + exclusive keyboard) via gtk4-layer-shell on wlroots/KDE. GNOME/Mutter does not expose layer-shell → fall back to one fullscreen always-above window per monitor |
| Seconds since last input | `CGEventSource.secondsSinceLastEventType` | Wayland: `ext-idle-notify-v1` (wlroots), `org.gnome.Mutter.IdleMonitor` (GNOME), `org.freedesktop.ScreenSaver.GetSessionIdleTime` (KDE). X11: `XScreenSaverQueryInfo` |
| Sleep/wake re-arm | `NSWorkspace.didWakeNotification` | `org.freedesktop.login1.Manager.PrepareForSleep` DBus signal |
| Multi-monitor + hotplug | `NSScreen.screens` + `didChangeScreenParameters` | `GdkDisplay.monitors` change notifications / `wl_output` events |
| Chimes | `NSSound(named:)` | `libcanberra` event sounds, or `paplay`/`pw-play` on a bundled ogg |
| Launch at login | `SMAppService.mainApp` | `~/.config/autostart/blink.desktop` (or a systemd `--user` service) |
| Settings persistence | `UserDefaults` | TOML/JSON under `$XDG_CONFIG_HOME/blink/config.toml` |

Everything on the right exists and is stable. Nothing here is a dead end.

## Recommended stack

**Rust + GTK4 + gtk4-layer-shell + ksni + zbus**, as a second crate in this repo
(`linux/`), sharing only the spec below rather than code.

Why:
- Single static-ish binary, no runtime, packages cleanly as Flatpak/AUR/deb.
- gtk4-layer-shell is the only realistic way to get a genuinely un-escapable
  overlay on Wayland, and it is a first-class Rust binding.
- `ksni` gives a tray without dragging in GTK's deprecated `GtkStatusIcon`.
- `zbus` covers logind (sleep), Mutter/KDE idle monitors, and notifications.

Alternatives considered:
- **Swift on Linux.** Would let the engine be literally shared, and swift-corelibs
  Foundation is fine, but the GTK bindings are immature and the tray story is
  worse. Not worth it for 300 lines of shared logic.
- **Tauri / Electron.** Fastest to a demo and truly one codebase, but no
  layer-shell means the overlay is escapable, and a browser engine per idle
  timer is a poor trade for a background utility.

## Behaviour spec to hold both ports to

The macOS build defines the contract; a Linux port is "correct" when it matches:

1. Phases: `working → warning → resting → working`, plus `paused(until:)`.
2. A single ~0.5 s tick recomputes from wall-clock deadlines, so sleep, suspend
   and clock changes can never leave a stale timer.
3. Idle ≥ break duration while working resets the next-break deadline.
4. Wake from sleep re-arms a full interval instead of firing immediately.
5. Heads-up HUD appears `warningLeadSeconds` before the break, top-right of the
   primary monitor, non-interactive.
6. Break overlay covers every monitor; only the primary one shows controls.
7. Overlay content fades to ~12 % opacity between 18 % and 82 % of the break, and
   returns for the last 3 s with a "Welcome back" message.
8. Chime at start and end (so the break can be taken with eyes closed).
9. Esc / Skip / Postpone honoured unless strict mode; strict mode swallows Esc.
10. Completed breaks increment a per-day counter; skipped ones do not.
11. Config keys keep the same names as the macOS `UserDefaults` keys.

## Degradations to accept up front

- **GNOME Wayland**: no layer-shell → the overlay is a fullscreen always-above
  window; a determined user can switch workspaces away from it. Strict mode
  becomes "strongly discouraging" rather than absolute.
- **GNOME tray**: without the AppIndicator extension there is no tray icon. Ship
  a `blink` CLI (`blink break-now`, `blink pause 1h`, `blink status`) over a unix
  socket so the app stays fully controllable, and use desktop notifications for
  the heads-up instead of a custom HUD if layer-shell is unavailable.
- **Global keyboard grab**: Wayland has no global key monitor. Esc-to-skip works
  only while the overlay has keyboard focus, which layer-shell's exclusive
  keyboard mode provides; the fallback path relies on window focus.

## Prior art worth checking before writing any of it

**SafeEyes** (Python/GTK) and **Stretchly** (Electron) already do 20-20-20 on
Linux and handle the tray/idle mess. If the goal is "rest my eyes on Linux",
install SafeEyes. If the goal is "the exact Blink UX on both machines", the Rust
plan above is the way, and it is roughly a day of work for parity minus the
GNOME caveats.
