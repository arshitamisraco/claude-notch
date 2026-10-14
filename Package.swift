// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeNotch", path: "Sources/ClaudeNotch"),
        .testTarget(name: "ClaudeNotchTests", dependencies: ["ClaudeNotch"], path: "Tests/ClaudeNotchTests"),
    ]
)
