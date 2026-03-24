// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AFTerminal",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AFTerminal", targets: ["AFTerminal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.12.0"),
    ],
    targets: [
        .target(
            name: "AFTerminal",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(name: "AFTerminalTests", dependencies: ["AFTerminal"]),
    ]
)
