// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WoofCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WoofCore", targets: ["WoofCore"]),
    ],
    targets: [
        .target(name: "WoofCore"),
        .testTarget(name: "WoofCoreTests", dependencies: ["WoofCore"]),
    ]
)
