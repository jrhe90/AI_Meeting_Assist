// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioCapture",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AudioCapture", targets: ["AudioCapture"]),
    ],
    dependencies: [
        .package(path: "../SharedKit"),
    ],
    targets: [
        .target(
            name: "AudioCapture",
            dependencies: ["SharedKit"]
        ),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture"]
        ),
    ]
)
