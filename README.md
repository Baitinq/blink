# Blink

A small cross-platform utility that makes you rest your eyes. Built on the
20-20-20 rule: every 20 minutes, look at something 20 feet away for 20 seconds.

- **macOS** — a native menu-bar app (AppKit + SwiftUI), no dock icon.
- **Linux** — an X11 daemon (Xlib + cairo) with a control CLI.

Shared behaviour lives in one place; each platform only supplies its window,
input and notification plumbing.

## Why it works

- **Unmissable, not annoying.** A heads-up appears ~10 s before a break so it
  never lands mid-keystroke. Then the screen fades to a calm dark overlay across
  *every* display.
- **Nothing to look at.** Mid-break the overlay dims almost to black on purpose —
  if there is nothing on screen, your eyes actually leave it.
- **Chimes at both ends.** So you can shut your eyes or stare out the window and
  still know when it is over, without peeking.
- **Never during a meeting.** A due break waits while a calendar event is in
  progress and starts the moment you are free. macOS reads the calendars already
  in Calendar.app, so a Google account works over CalDAV with no OAuth, no
  credentials and nothing to configure.
- **Away time counts.** Leave the keyboard for a full break length and the timer
  resets — no pointless interruption when you get back from coffee.
- **Hard to cancel by accident.** The overlay lands under wherever your pointer
  already is, so for the first 1.5 s nothing is accepted at all; after that it
  takes two of anything — click Skip twice, or press Esc twice. *Strict mode*
  removes the hatches entirely.

## Install — macOS

```sh
packaging/macos/build.sh --install   # self-test, build, sign, install to Applications, launch
packaging/macos/build.sh            # build only → .build/Blink.app
```

Look for the eye in the menu bar. Turn on **Launch at login** in Settings.

Menu: countdown and breaks-today · Break now · Skip · Pause (20 m / 1 h / 3 h /
until resume) · Settings (⌘,) · Quit (⌘Q). During a break, click **Skip** twice
or press **esc** twice. Only one copy of Blink runs at a time; a second launch
bows out rather than doubling your breaks.

## Install — Linux

Requires an X11 session, or a Wayland session with XWayland.

```sh
# Debian/Ubuntu: apt install libx11-dev libxss-dev libxrandr-dev libcairo2-dev pkg-config
# Fedora:        dnf install libX11-devel libXScrnSaver-devel libXrandr-devel cairo-devel
packaging/linux/install.sh
```

```
blink                    run the daemon (--verbose to log to stdout)
blink status             "next break in 12:04  ·  3 today"
blink break | skip | postpone | resume
blink pause 20m | 1h | inf
blink set breakDurationSeconds 30
blink calendar <ical-url> hold breaks during meetings (Google: "Secret address in iCal format")
blink config             config path + contents
```

The daemon publishes `$XDG_RUNTIME_DIR/blink/status.json`, so a waybar/polybar
module is a one-liner, and takes commands on a FIFO next to it. During a break,
**esc esc** skips and **p p** postpones.

## Meetings

On macOS this needs one thing: allow Calendar access when Blink asks (once, at
first launch). It then holds any due break while an event is in progress and
starts it as soon as the meeting ends — the menu bar shows *Break held — in
Weekly sync*, with **Break now anyway** if you want it regardless.

All-day events, declined invitations and anything marked *free* are ignored, so
"PTO" or a reminder will not suppress your breaks all day. By default only events
with other attendees or a video link count, so focus blocks still get breaks.

Linux has no Calendar.app, so point it at a calendar's private iCal address:

```sh
blink calendar https://calendar.google.com/calendar/ical/.../basic.ics
blink calendar off
```

Recurring meetings are expanded locally (daily and weekly rules, including
`BYDAY`, `EXDATE`, `COUNT` and `UNTIL`). Note that Google's secret iCal feed can
lag behind the live calendar, so a meeting created minutes ago may not hold a
break yet.

## Settings

Same keys on both platforms — `UserDefaults` on macOS,
`$XDG_CONFIG_HOME/blink/config.json` on Linux.

| Key | Default |
| --- | --- |
| `workIntervalMinutes` | 20 |
| `breakDurationSeconds` | 20 |
| `warningLeadSeconds` | 10 |
| `postponeMinutes` | 5 |
| `strictMode` | false |
| `fadeToBlack` | true |
| `playSounds` | true |
| `idleResetEnabled` | true |
| `skipDuringMeetings` | true |
| `meetingsNeedAttendees` | true |
| `calendarICSURL` (Linux) | — |
| `showPreBreakWarning` | true |
| `showCountdownInMenuBar` | false |

## Architecture

`BlinkCore` is the whole behaviour of the app and imports **Foundation only** —
no AppKit, no SwiftUI, no Combine, no X11. It talks to the outside world through
seven small ports; a platform is just a bundle of adapters.

```
                    ┌───────────────────────────────┐
                    │          BlinkCore            │
                    │  BreakEngine   BlinkSettings  │
                    │  Phase  Prompts  Format       │
                    └───────────────┬───────────────┘
        ports:  SettingsStore · IdleMonitor · SystemEvents · SoundPlayer
                BreakOverlay · WarningHUD · StatusDisplay · Scheduler · Clock
        ┌───────────────────────────┴───────────────────────────┐
        │                                                       │
┌───────────────────────────────┐         ┌───────────────────────────────┐
│           BlinkMac            │         │          BlinkLinux           │
│ NSStatusItem      menu + UI   │         │ ControlSurface  FIFO + JSON   │
│ NSPanel @.screenSaver ×screen │         │ X11Overlay      override-      │
│ SwiftUI overlay + settings    │         │   redirect window + cairo      │
│ CGEventSource idle            │         │ XScreenSaver / DBus idle      │
│ NSWorkspace wake              │         │ logind PrepareForSleep        │
│ UserDefaults · NSSound        │         │ JSON file · canberra/paplay   │
└───────────────────────────────┘         └───────────────────────────────┘
```

The engine never counts down; it recomputes from wall-clock deadlines every
tick, so suspend, clock changes and a stalled run loop cannot desynchronise it.

```
Package.swift
src/
  BlinkCore/       Ports · BreakEngine · Settings · Presentation (prompts, formats,
                   fade curve, pause grammar)
  BlinkMac/        App · MacPlatform · MacBreakOverlay · BreakOverlayView
                   MacWarningHUD · MenuBarController · SettingsWindow
  BlinkLinux/      main (daemon + CLI) · LinuxPlatform · X11Overlay
                   LinuxIdle · Notifications · ControlSurface · JSONStore · Shell
  BlinkSelfTest/   29 deterministic tests, fake clock and fake platform, no XCTest
  CX11/ CCairo/    system-library modulemaps
packaging/macos/   build.sh (bundle + icon + sign + install) · makeicon.swift
packaging/linux/   install.sh · systemd unit · autostart entry
                   Dockerfile + smoke.sh (build and screenshot the overlay on Xvfb)
```

Anything platform-shaped that is nonetheless pure logic — the fade curve, the
`20m`/`1h`/`inf` grammar, time formatting — lives in `BlinkCore` and is covered by
the self-test, so the two renderers cannot drift apart.

## Tests

```sh
swift run blink-selftest                                  # 33 tests, both platforms, ~10 ms
docker build -f packaging/linux/Dockerfile -t blink-linux . \
  && docker run --rm -v "$PWD/out":/out blink-linux       # Linux: overlay screenshots + input guards
packaging/macos/headless-test.sh                          # macOS AppKit layer, nothing on screen
packaging/macos/verify.sh                                 # live macOS app: takes over the screen
```

The self-test drives the engine through a fake clock and fake platform, so a
full 20-minute cycle, sleep/wake, idle credit, pause expiry, display hotplug and
the accidental-skip guard are verified without waiting or opening a window.

The container run is the one to prefer: inside Xvfb it drives the real overlay
with `xdotool` and asserts the guards (two escapes during the grace period are
ignored, one escape does not skip, two escapes do) without touching your session.

`headless-test.sh` covers the AppKit pieces the other two cannot reach — the
overlay's escape-hatch gates, the settings window building and writing through,
the menu bar rendering every phase — with the activation policy set to
`.prohibited`, so nothing is ever shown.

`packaging/macos/verify.sh` checks the real bundle — scratch defaults domain so
it cannot rewrite your settings, single-instance assertion, an actual break timed
to the second, cleanup on exit — but it does put a full-screen overlay on your
display, so run it when you are not mid-task.

## Linux caveats

The overlay is an override-redirect X11 window: under Xorg nothing can stack
above it and `XGrabKeyboard` swallows every keystroke. Under XWayland the
compositor owns stacking, so a native Wayland window can cover it and the grab
only reaches X clients — strict mode becomes strongly discouraging rather than
absolute. Idle detection switches to the compositor's DBus idle monitor on
Wayland, because XWayland's own idle clock cannot see Wayland-native input and
would otherwise cancel every break while you type.

Adding a `gtk4-layer-shell` overlay would fix stacking and the grab on wlroots
and KDE; it is one more `BreakOverlay` implementation and nothing else changes.
