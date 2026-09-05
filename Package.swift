// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexStatus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexStatus", targets: ["CodexStatus"]),
        .executable(name: "CodexStatusHook", targets: ["CodexStatusHook"]),
        .executable(name: "CodexStatusThreadScanner", targets: ["CodexStatusThreadScanner"]),
        .executable(name: "CodexStatusProgress", targets: ["CodexStatusProgress"]),
        .executable(name: "CodexStatusWatcher", targets: ["CodexStatusWatcher"])
    ],
    targets: [
        .executableTarget(
            name: "CodexStatus",
            path: "Sources/CodexStatus"
        ),
        .executableTarget(
            name: "CodexStatusHook",
            path: "Sources/CodexStatusHook"
        ),
        .executableTarget(
            name: "CodexStatusThreadScanner",
            path: "Sources/CodexStatusThreadScanner"
        ),
        .executableTarget(
            name: "CodexStatusProgress",
            path: "Sources/CodexStatusProgress"
        ),
        .executableTarget(
            name: "CodexStatusWatcher",
            path: "Sources/CodexStatusWatcher"
        )
    ]
)
