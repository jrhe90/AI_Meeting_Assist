// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Transcription",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Transcription", targets: ["Transcription"]),
    ],
    dependencies: [
        .package(path: "../SharedKit"),
    ],
    targets: [
        .target(
            name: "Transcription",
            dependencies: ["SharedKit"]
        ),
        .testTarget(
            name: "TranscriptionTests",
            dependencies: ["Transcription"]
        ),
    ]
)
