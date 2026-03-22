// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFDiff",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AFDiff", targets: ["AFDiff"]),
    ],
    dependencies: [
        .package(path: "../AFCore"),
    ],
    targets: [
        .target(name: "AFDiff", dependencies: ["AFCore"]),
        .testTarget(name: "AFDiffTests", dependencies: ["AFDiff"]),
    ]
)
