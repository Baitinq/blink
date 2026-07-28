// swift-tools-version:5.9
import PackageDescription

// The core is portable; the executable is not. Each platform target implements
// the same seven ports from BlinkCore.
var targets: [Target] = [
    // Foundation only: no AppKit, no SwiftUI, no Combine, no GTK, no X11.
    .target(name: "BlinkCore", path: "src/BlinkCore"),
    // Dependency-free suite: `swift run blink-selftest` (no Xcode needed, runs on Linux too).
    .executableTarget(name: "blink-selftest", dependencies: ["BlinkCore"], path: "src/BlinkSelfTest"),
]

#if os(macOS)
targets.append(
    .executableTarget(name: "blink", dependencies: ["BlinkCore"], path: "src/BlinkMac")
)
#else
targets.append(contentsOf: [
    .systemLibrary(name: "CX11", path: "src/CX11", pkgConfig: "x11",
                   providers: [.apt(["libx11-dev", "libxss-dev", "libxrandr-dev"])]),
    .systemLibrary(name: "CCairo", path: "src/CCairo", pkgConfig: "cairo",
                   providers: [.apt(["libcairo2-dev"])]),
    .executableTarget(name: "blink", dependencies: ["BlinkCore", "CX11", "CCairo"],
                      path: "src/BlinkLinux"),
])
#endif

let package = Package(
    name: "Blink",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "blink", targets: ["blink"]),
        .executable(name: "blink-selftest", targets: ["blink-selftest"]),
        .library(name: "BlinkCore", targets: ["BlinkCore"]),
    ],
    targets: targets
)
