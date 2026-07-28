// Counts Blink's on-screen overlay windows (screen-saver level), for verify.sh.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let overlays = windows.filter {
    ($0["kCGWindowOwnerName"] as? String) == "Blink" && ($0["kCGWindowLayer"] as? Int ?? 0) >= 1000
}
print(overlays.count)
