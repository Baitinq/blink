// Renders Blink's app icon (dark rounded square + teal eye) into an .iconset.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(size: CGFloat) -> Data {
    let image = NSImage(size: CGSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)
    path.addClip()

    let colors = [
        NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.13, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1).cgColor,
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // glow behind the eye
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.78, alpha: 0.30).cgColor,
        NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.78, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
                           endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size * 0.45, options: [])

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .light)
    if let symbol = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            NSColor(calibratedRed: 0.42, green: 0.92, blue: 0.85, alpha: 1).set()
            r.fill(using: .sourceOver)
            symbol.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        let s = tinted.size
        tinted.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                   (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
                   (512, "512x512"), (1024, "512x512@2x")] {
    let data = render(size: CGFloat(px))
    try data.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("icons written to \(out)")
