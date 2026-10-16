// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibeMirror",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VibeMirror",
            path: "Sources/VibeMirror"
        )
    ],
    swiftLanguageModes: [.v5]
)
