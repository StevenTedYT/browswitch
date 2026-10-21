// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Browswitch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BrowswitchCore"),
        .executableTarget(name: "Browswitch", dependencies: ["BrowswitchCore"]),
        .testTarget(name: "BrowswitchCoreTests", dependencies: ["BrowswitchCore"]),
    ]
)
