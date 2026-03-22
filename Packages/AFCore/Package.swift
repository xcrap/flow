// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AFCore", targets: ["AFCore"]),
    ],
    targets: [
        .target(name: "AFCore"),
        .testTarget(name: "AFCoreTests", dependencies: ["AFCore"]),
    ]
)
