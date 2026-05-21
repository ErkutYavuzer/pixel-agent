// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "pixel-agent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PixelCore", targets: ["PixelCore"]),
        .library(name: "PixelBackends", targets: ["PixelBackends"]),
        .library(name: "PixelTools", targets: ["PixelTools"]),
        .library(name: "PixelMemory", targets: ["PixelMemory"]),
        .library(name: "PixelMascot", targets: ["PixelMascot"]),
        .library(name: "PixelRemote", targets: ["PixelRemote"]),
        .executable(name: "PixelMacApp", targets: ["PixelMacApp"]),
    ],
    targets: [
        .target(name: "PixelCore"),
        .target(name: "PixelBackends", dependencies: ["PixelCore"]),
        .target(name: "PixelTools", dependencies: ["PixelCore"]),
        .target(name: "PixelMemory", dependencies: ["PixelCore"]),
        .target(name: "PixelMascot"),
        .target(name: "PixelRemote", dependencies: ["PixelCore"]),
        .executableTarget(
            name: "PixelMacApp",
            dependencies: [
                "PixelCore",
                "PixelBackends",
                "PixelTools",
                "PixelMemory",
                "PixelMascot",
                "PixelRemote",
            ]
        ),
        .testTarget(name: "PixelCoreTests", dependencies: ["PixelCore"]),
        .testTarget(name: "PixelBackendsTests", dependencies: ["PixelBackends"]),
        .testTarget(name: "PixelToolsTests", dependencies: ["PixelTools"]),
        .testTarget(name: "PixelMemoryTests", dependencies: ["PixelMemory"]),
        .testTarget(name: "PixelMascotTests", dependencies: ["PixelMascot"]),
        .testTarget(name: "PixelRemoteTests", dependencies: ["PixelRemote"]),
        .testTarget(name: "PixelMacAppTests", dependencies: ["PixelMacApp"]),
    ],
    swiftLanguageModes: [.v6]
)
