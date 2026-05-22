// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "pixel-agent",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PixelCore", targets: ["PixelCore"]),
        .library(name: "PixelBackends", targets: ["PixelBackends"]),
        .library(name: "PixelTools", targets: ["PixelTools"]),
        .library(name: "PixelMemory", targets: ["PixelMemory"]),
        .library(name: "PixelMascot", targets: ["PixelMascot"]),
        .library(name: "PixelRemote", targets: ["PixelRemote"]),
        .library(name: "PixelLAN", targets: ["PixelLAN"]),
        .library(name: "PixelSubagent", targets: ["PixelSubagent"]),
        .library(name: "PixelMCPServer", targets: ["PixelMCPServer"]),
        .executable(name: "PixelMacApp", targets: ["PixelMacApp"]),
        .executable(name: "pixel-mcp-server", targets: ["pixel-mcp-server"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(name: "PixelCore"),
        .target(name: "PixelBackends", dependencies: ["PixelCore"]),
        .target(name: "PixelTools", dependencies: ["PixelCore"]),
        .target(name: "PixelMemory", dependencies: ["PixelCore"]),
        .target(name: "PixelMascot"),
        .target(name: "PixelRemote", dependencies: ["PixelCore"]),
        .target(name: "PixelLAN", dependencies: ["PixelRemote"]),
        .target(name: "PixelSubagent", dependencies: ["PixelCore"]),
        .target(name: "PixelMCPServer"),
        .executableTarget(
            name: "pixel-mcp-server",
            dependencies: ["PixelMCPServer"]
        ),
        .executableTarget(
            name: "PixelMacApp",
            dependencies: [
                "PixelCore",
                "PixelBackends",
                "PixelTools",
                "PixelMemory",
                "PixelMascot",
                "PixelRemote",
                "PixelSubagent",
                "PixelMCPServer",
            ]
        ),
        .testTarget(name: "PixelCoreTests", dependencies: ["PixelCore"]),
        .testTarget(name: "PixelBackendsTests", dependencies: ["PixelBackends"]),
        .testTarget(name: "PixelToolsTests", dependencies: ["PixelTools"]),
        .testTarget(name: "PixelMemoryTests", dependencies: ["PixelMemory"]),
        .testTarget(name: "PixelMascotTests", dependencies: ["PixelMascot"]),
        .testTarget(name: "PixelRemoteTests", dependencies: ["PixelRemote"]),
        .testTarget(name: "PixelLANTests", dependencies: ["PixelLAN"]),
        .testTarget(name: "PixelSubagentTests", dependencies: ["PixelSubagent"]),
        .testTarget(name: "PixelMCPServerTests", dependencies: ["PixelMCPServer"]),
        .testTarget(name: "PixelMacAppTests", dependencies: ["PixelMacApp", "PixelMCPServer"]),
    ],
    swiftLanguageModes: [.v6]
)
