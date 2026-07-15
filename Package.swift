// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageTray",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeUsageTray",
            path: "Sources/ClaudeUsageTray"
        )
    ]
)
