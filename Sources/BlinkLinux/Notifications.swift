import Foundation
import BlinkCore

/// Pre-break heads-up as a desktop notification.
///
/// `x-canonical-private-synchronous` makes conforming daemons replace the
/// previous notification instead of stacking ten of them, which gives the same
/// in-place countdown as the macOS HUD.
final class NotifyWarningHUD: WarningHUD {
    private var total = 10
    private var lastShownSecond = -1

    func show(totalSeconds: Double) {
        total = Int(totalSeconds)
        lastShownSecond = -1
    }

    func update(secondsLeft: Int) {
        guard secondsLeft != lastShownSecond else { return }
        lastShownSecond = secondsLeft
        Shell.detach("notify-send", [
            "--app-name=Blink",
            "--urgency=low",
            "--expire-time=1200",
            "--icon=eye",
            "--hint=string:x-canonical-private-synchronous:blink",
            "--hint=int:value:\(Int(Double(total - secondsLeft) / Double(max(1, total)) * 100))",
            "Eye break in \(secondsLeft)s",
        ])
    }

    func hide() {
        lastShownSecond = -1
    }
}

/// Chimes so a break can be taken with your eyes shut, using whichever player
/// the distro happens to ship.
final class LinuxSoundPlayer: SoundPlayer {
    private static let candidates = [
        "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
        "/usr/share/sounds/freedesktop/stereo/bell.oga",
        "/usr/share/sounds/freedesktop/stereo/complete.oga",
    ]

    func play(_ cue: SoundCue) {
        let event = cue == .breakStart ? "message-new-instant" : "complete"
        if Shell.which("canberra-gtk-play") != nil {
            Shell.detach("canberra-gtk-play", ["-i", event])
            return
        }
        guard let file = Self.candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            FileHandle.standardError.write(Data("\u{7}".utf8))   // terminal bell, last resort
            return
        }
        for player in ["pw-play", "paplay", "aplay"] where Shell.which(player) != nil {
            Shell.detach(player, [file])
            return
        }
    }
}
