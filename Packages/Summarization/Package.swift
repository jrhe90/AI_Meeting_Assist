// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Summarization",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Summarization", targets: ["Summarization"]),
    ],
    dependencies: [
        .package(path: "../SharedKit"),
        .package(path: "../Transcription"),
    ],
    targets: [
        .target(
            name: "Summarization",
            dependencies: ["SharedKit", "Transcription"]
        ),
        .testTarget(
            name: "SummarizationTests",
            dependencies: ["Summarization"]
        ),
    ]
)
