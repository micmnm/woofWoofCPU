// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WoofCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WoofCore", targets: ["WoofCore"]),
    ],
    targets: [
        .target(name: "WoofCore", linkerSettings: [.linkedFramework("IOKit")]),
        .testTarget(name: "WoofCoreTests", dependencies: ["WoofCore"]),
    ]
)
