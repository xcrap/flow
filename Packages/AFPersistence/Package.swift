// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFPersistence",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AFPersistence", targets: ["AFPersistence"]),
    ],
    dependencies: [
        .package(path: "../AFCore"),
    ],
    targets: [
        .target(name: "AFPersistence", dependencies: ["AFCore"]),
        .testTarget(name: "AFPersistenceTests", dependencies: ["AFPersistence"]),
    ]
)
