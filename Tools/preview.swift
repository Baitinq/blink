// Offscreen renderer for design review: writes PNGs of the overlay + settings UI.
import SwiftUI
import AppKit

@MainActor
func snap<V: View>(_ view: V, size: CGSize, to path: String) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

@MainActor
func run() {
    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
    for (name, left) in [("start", 20.0), ("mid", 10.0), ("end", 2.0)] {
        let state = BreakState()
        state.total = 20
        state.secondsLeft = left
        state.prompt = "Out the window. Far corner of the room. Anywhere but here."
        snap(BreakOverlayView(showsControls: true).environmentObject(state),
             size: CGSize(width: 1000, height: 640), to: "\(out)/overlay-\(name).png")
    }
    snap(SettingsContent().padding(28).frame(width: 460, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 460, height: 620), to: "\(out)/settings.png")
    let warn = WarningState()
    warn.total = 10
    warn.secondsLeft = 6
    snap(WarningView().environmentObject(warn), size: CGSize(width: 250, height: 62), to: "\(out)/warning.png")
}

MainActor.assumeIsolated { run() }
