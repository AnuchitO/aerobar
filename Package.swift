// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Workspaces",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Workspaces",
            path: "Sources/Workspaces"
        )
    ]
)
