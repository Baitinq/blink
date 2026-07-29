import Foundation
import Dispatch
import BlinkCore

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    blink — eye break reminders (20-20-20)

    usage:
      blink [--verbose]        run the daemon
      blink status             print the current state
      blink break              start a break now
      blink skip               skip the current break or cycle
      blink postpone           postpone by the configured amount
      blink pause <20m|1h|inf> pause reminders
      blink resume             resume reminders
      blink set <key> <value>  change a setting
      blink calendar <url>     hold breaks during meetings from an iCal address
      blink config             print the config file path and contents

    config: $XDG_CONFIG_HOME/blink/config.json
    state:  $XDG_RUNTIME_DIR/blink/status.json  (for waybar/polybar)
    """)
    exit(arguments.isEmpty ? 0 : 1)
}

/// One-shot client commands talk to a running daemon over the control FIFO.
func runClient(_ command: String) -> Never {
    guard ControlSurface.send(command) else {
        FileHandle.standardError.write(Data("blink is not running\n".utf8))
        exit(1)
    }
    exit(0)
}

switch arguments.first {
case "status":
    guard let text = ControlSurface.readStatus() else {
        FileHandle.standardError.write(Data("blink is not running\n".utf8))
        exit(1)
    }
    print(text)
    exit(0)

case "break", "skip", "postpone", "resume":
    runClient(arguments[0])

case "pause":
    runClient("pause " + (arguments.count > 1 ? arguments[1] : "inf"))

case "calendar":
    let store = JSONFileStore()
    let settings = BlinkSettings(store: store)
    if arguments.count > 1 {
        settings.calendarICSURL = arguments[1] == "off" ? nil : arguments[1]
    }
    print(settings.calendarICSURL ?? "(no calendar configured)")
    exit(0)

case "config":
    let store = JSONFileStore()
    print(store.path)
    print((try? String(contentsOfFile: store.path, encoding: .utf8)) ?? "{}")
    exit(0)

case "set":
    guard arguments.count == 3 else { usage() }
    let store = JSONFileStore()
    let key = SettingKey(arguments[1])
    guard BlinkSettings.defaults[key] != nil else {
        FileHandle.standardError.write(Data("unknown setting '\(arguments[1])'\n".utf8))
        exit(1)
    }
    let raw = arguments[2]
    if let number = Int(raw) {
        store.set(number, for: key)
    } else if let flag = Bool(raw) {
        store.set(flag, for: key)
    } else {
        store.set(raw, for: key)
    }
    print("\(arguments[1]) = \(raw)")
    exit(0)

case "-h", "--help", "help":
    usage()

case .some(let unknown) where unknown != "--verbose":
    FileHandle.standardError.write(Data("unknown command '\(unknown)'\n".utf8))
    usage()

default:
    break
}

// MARK: - Daemon

let verbose = arguments.contains("--verbose")

let store = JSONFileStore()
let settings = BlinkSettings(store: store)

guard let platform = LinuxPlatform(verbose: verbose, store: store, settings: settings) else {
    FileHandle.standardError.write(Data("""
    blink: no X display found.

    Blink's overlay is an X11 window. Under Xorg it runs natively; under a
    Wayland compositor it runs through XWayland — make sure XWayland is enabled
    and DISPLAY is set.
    """.utf8))
    exit(1)
}

let engine = BreakEngine(settings: settings, platform: platform)
engine.start()

if verbose {
    print("blink running · every \(settings.workIntervalMinutes) min for \(settings.breakDurationSeconds)s")
    print("idle source: \(platform.describeIdleBackend)")
    print("control: \(ControlSurface.controlPath.path)")
}

var signalSources: [DispatchSourceSignal] = []

// Leave gracefully so the FIFO and the X grab do not outlive the process.
for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        engine.stop()
        platform.overlay.dismiss()
        try? FileManager.default.removeItem(at: ControlSurface.statusPath)
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

dispatchMain()
