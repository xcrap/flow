// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFAgent",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AFAgent", targets: ["AFAgent"]),
    ],
    dependencies: [
        .package(path: "../AFCore"),
    ],
    targets: [
        .target(name: "AFAgent", dependencies: ["AFCore"]),
        .testTarget(name: "AFAgentTests", dependencies: ["AFAgent"]),
    ]
)
