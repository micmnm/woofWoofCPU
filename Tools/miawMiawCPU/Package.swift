// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "miawMiawCPU",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MiawCore"),
        .executableTarget(name: "miawMiawCPU", dependencies: ["MiawCore"]),
        .testTarget(name: "MiawCoreTests", dependencies: ["MiawCore"]),
    ]
)
