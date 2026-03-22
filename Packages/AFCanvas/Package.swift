// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFCanvas",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AFCanvas", targets: ["AFCanvas"]),
    ],
    dependencies: [
        .package(path: "../AFCore"),
    ],
    targets: [
        .target(name: "AFCanvas", dependencies: ["AFCore"]),
        .testTarget(name: "AFCanvasTests", dependencies: ["AFCanvas"]),
    ]
)
