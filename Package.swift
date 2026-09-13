// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AeroBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AeroBar",
            path: "Sources/AeroBar"
        )
    ]
)
