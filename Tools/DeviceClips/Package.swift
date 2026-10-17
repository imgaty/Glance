// swift-tools-version:5.9
import PackageDescription

// Draws the clips Glance shows AirPods and Beats turning in, from Apple's and Beats' own 3D
// models, into Resources/Headphones. Run it only to add or redo a model:
//   swift run --package-path Tools/DeviceClips device-clips [name ...]
let package = Package(
    name: "DeviceClips",
    platforms: [.macOS("26.0")],
    targets: [.executableTarget(name: "device-clips", path: "Sources/DeviceClips")]
)
