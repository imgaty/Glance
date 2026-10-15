// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Glance", targets: ["Glance"]),
        // Loaded by /usr/bin/perl, not the app; see NowPlayingHelper.swift.
        .library(name: "GlanceNowPlaying", type: .dynamic, targets: ["NowPlayingHelper"]),
        // Glance Tray in the Share menu, an app extension inside the app; see ShareViewController.swift.
        .executable(name: "GlanceShare", targets: ["GlanceShare"]),
    ],
    dependencies: [
        // Check for Updates…: finds, downloads and installs new versions from GitHub Releases.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Glance", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources/Glance"),
        .target(name: "NowPlayingHelper", path: "Sources/NowPlayingHelper"),
        // An app extension starts in NSExtensionMain, and may use only what extensions are allowed to.
        .executableTarget(
            name: "GlanceShare", path: "Sources/GlanceShare",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-application-extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        .testTarget(name: "GlanceTests", dependencies: ["Glance"], path: "Tests/GlanceTests"),
    ]
)
