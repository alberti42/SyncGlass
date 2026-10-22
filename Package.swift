// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SyncGlass",
    platforms: [.macOS(.v26)],
    targets: [
        // The menu-bar app.
        .executableTarget(
            name: "SyncGlass",
            path: "Sources/SyncGlass",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Login item embedded in SyncGlass.app/Contents/Library/LoginItems.
        .executableTarget(
            name: "LoginHelper",
            path: "Sources/LoginHelper",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Unit tests for the parts that do not need iCloud Drive: `swift test`.
        .testTarget(
            name: "SyncGlassTests",
            dependencies: ["SyncGlass"],
            path: "Tests/SyncGlassTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
