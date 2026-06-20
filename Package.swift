// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexStatusIsland",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexStatusIsland", targets: ["CodexStatusIsland"])
    ],
    targets: [
        .executableTarget(
            name: "CodexStatusIsland",
            path: "Sources/CodexStatusIsland"
        )
    ]
)
