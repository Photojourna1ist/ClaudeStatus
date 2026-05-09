// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeStatusCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeStatusCore", targets: ["ClaudeStatusCore"])
    ],
    targets: [
        .target(name: "ClaudeStatusCore")
    ]
)
