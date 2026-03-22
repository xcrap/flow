// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFTerminal",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AFTerminal", targets: ["AFTerminal"]),
    ],
    targets: [
        .target(name: "AFTerminal"),
        .testTarget(name: "AFTerminalTests", dependencies: ["AFTerminal"]),
    ]
)
