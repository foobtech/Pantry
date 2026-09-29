// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "PantryCore",
    platforms: [.iOS(.v11), .macOS(.v10_13)],
    products: [
        .library(name: "PantryCore", targets: ["PantryCore"]),
        .executable(name: "pantry-cli", targets: ["pantry-cli"]),
    ],
    targets: [
        .target(name: "PantryCore"),
        .target(name: "pantry-cli", dependencies: ["PantryCore"]),
        .testTarget(name: "PantryCoreTests", dependencies: ["PantryCore"]),
    ]
)
