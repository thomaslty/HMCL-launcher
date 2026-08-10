// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HMCLLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LauncherKit"),
        .executableTarget(
            name: "HMCLLauncher",
            dependencies: ["LauncherKit"]
        ),
        .testTarget(
            name: "LauncherKitTests",
            dependencies: ["LauncherKit"]
        ),
    ]
)
