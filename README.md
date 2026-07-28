# Blink

A tiny native macOS menu-bar app that makes you rest your eyes. Built on the
20-20-20 rule: every 20 minutes, look at something 20 feet away for 20 seconds.

## Why it works

- **Unmissable, not annoying.** A 10-second heads-up HUD appears in the top-right
  corner so a break never lands mid-keystroke. Then the screen fades to a calm
  dark overlay across *every* display.
- **Nothing to look at.** Mid-break the overlay dims almost to black on purpose —
  if there is nothing on screen, your eyes actually leave it.
- **Chimes at both ends.** Start and end sounds mean you can shut your eyes or
  stare out the window and still know when the break is over, without peeking.
- **Away time counts.** If you leave the keyboard for a full break length, the
  timer resets — no pointless interruption when you get back from coffee.
- **Escape hatches, or not.** Skip / Postpone by default; turn on *Strict mode*
  when you want to be held to it.

## Install

```sh
./build.sh --install     # builds, signs, installs to /Applications (or ~/Applications) and launches
./build.sh               # build only, output in build/Blink.app
```

Look for the eye icon in the menu bar. Turn on **Launch at login** in Settings.

## Menu bar

- Next break countdown and today's break count
- **Break now** / **Skip this cycle**
- **Pause** for 20 min / 1 hour / 3 hours / until you resume
- **Settings…** (⌘,) and **Quit** (⌘Q)

## Settings

| Setting | Default |
| --- | --- |
| Break every | 20 min |
| Break lasts | 20 s |
| Heads-up before | 10 s |
| Postpone adds | 5 min |
| Strict mode | off |
| Fade the screen to black | on |
| Chime at start and end | on |
| Time away counts as a break | on |
| Show countdown in the menu bar | off |
| Launch at login | off |

During a break: **esc** skips (unless strict mode).

## Layout

```
Sources/Blink/
  App.swift              NSApplication bootstrap (accessory app, no dock icon)
  BreakEngine.swift      work/warning/rest/pause state machine, idle + wake handling
  Overlay.swift          full-screen break windows, one per display
  BreakOverlayView.swift the break UI (countdown ring, prompts, controls)
  WarningPanel.swift     pre-break heads-up HUD
  MenuBarController.swift status item and menu
  Settings.swift         UserDefaults-backed settings + daily stats
  SettingsWindow.swift   settings UI, launch-at-login
Tools/
  makeicon.swift         renders the app icon into an .iconset
  preview.swift          offscreen PNG renders of the UI for design review
build.sh                 build → bundle → icon → codesign → install
```

Requires macOS 13+. No dependencies, no network access, no permissions needed.

## Linux?

Not today — the UI is AppKit/SwiftUI. See [docs/LINUX.md](docs/LINUX.md) for a
concrete port plan (Rust + GTK4 + layer-shell + StatusNotifierItem) and the
behaviour spec both ports should satisfy.
