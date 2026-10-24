// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SyncGlass",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Software updates. bin/build-app.sh embeds Sparkle.framework in the app.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // The menu-bar app.
        .executableTarget(
            name: "SyncGlass",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SyncGlass",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // SwiftPM sets no run path for Sparkle.framework. It lies next to the
            // executable in .build/debug, and in Contents/Frameworks of the app.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            ])]
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
