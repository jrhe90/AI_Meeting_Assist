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
        // Built from Vendor/whisper.cpp via build-xcframework.sh — see README.
        // The xcframework lives outside the package so the repo doesn't bloat
        // with prebuilt binaries; rebuild it whenever whisper.cpp is bumped.
        .binaryTarget(
            name: "whisper",
            path: "../../Vendor/whisper.cpp/build-apple/whisper.xcframework"
        ),
        .target(
            name: "Transcription",
            dependencies: ["SharedKit", "whisper"]
        ),
        .testTarget(
            name: "TranscriptionTests",
            dependencies: ["Transcription"]
        ),
    ]
)
