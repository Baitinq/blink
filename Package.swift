// swift-tools-version:5.9
import PackageDescription

// The core is portable; the executable is not. Each platform target implements
// the same seven ports from BlinkCore.
var targets: [Target] = [
    // Foundation only: no AppKit, no SwiftUI, no Combine, no GTK, no X11.
    .target(name: "BlinkCore", path: "Sources/BlinkCore"),
    // Dependency-free suite: `swift run blink-selftest` (no Xcode needed, runs on Linux too).
    .executableTarget(name: "blink-selftest", dependencies: ["BlinkCore"], path: "Sources/BlinkSelfTest"),
]

#if os(macOS)
targets.append(
    .executableTarget(name: "blink", dependencies: ["BlinkCore"], path: "Sources/BlinkMac")
)
#else
targets.append(contentsOf: [
    .systemLibrary(name: "CX11", path: "Sources/CX11", pkgConfig: "x11",
                   providers: [.apt(["libx11-dev", "libxss-dev", "libxrandr-dev"])]),
    .systemLibrary(name: "CCairo", path: "Sources/CCairo", pkgConfig: "cairo",
                   providers: [.apt(["libcairo2-dev"])]),
    .executableTarget(name: "blink", dependencies: ["BlinkCore", "CX11", "CCairo"],
                      path: "Sources/BlinkLinux"),
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
