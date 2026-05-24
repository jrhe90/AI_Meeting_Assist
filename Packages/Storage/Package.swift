// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Storage",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Storage", targets: ["Storage"]),
    ],
    dependencies: [
        .package(path: "../SharedKit"),
        .package(path: "../Transcription"),
        .package(path: "../Summarization"),
    ],
    targets: [
        .target(
            name: "Storage",
            dependencies: ["SharedKit", "Transcription", "Summarization"]
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage"]
        ),
    ]
)
