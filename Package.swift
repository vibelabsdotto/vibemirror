// swift-tools-version: 6.0

import Foundation
import PackageDescription

// The AirPlay receiver links libcrypto (OpenSSL) and libplist statically.
// scripts/build-deps.sh builds universal copies for macOS 14+ into .deps/.
let deps = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".deps").path

let package = Package(
    name: "VibeMirror",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CAirPlay",
            path: "Sources/CAirPlay",
            exclude: [
                "uxplay/LICENSE",
                "uxplay/UPSTREAM.md",
                "uxplay/lib/playfair/LICENSE.md",
                "uxplay/lib/llhttp/LICENSE-MIT",
            ],
            cSettings: [
                .headerSearchPath("uxplay/lib"),
                .headerSearchPath("uxplay/lib/playfair"),
                .headerSearchPath("uxplay/lib/llhttp"),
                .define("EXTERNAL_DNS_SD"),
                .define("NOHOLD"),
                .define("PLIST_210"),
                .define("PLIST_230"),
                .unsafeFlags([
                    "-I\(deps)/include",
                    "-w",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "\(deps)/lib/libcrypto.a",
                    "\(deps)/lib/libplist-2.0.a",
                ]),
            ]
        ),
        .executableTarget(
            name: "VibeMirror",
            dependencies: ["CAirPlay"],
            path: "Sources/VibeMirror"
        ),
    ],
    swiftLanguageModes: [.v5]
)
