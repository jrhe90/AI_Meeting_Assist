// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SharedKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SharedKit", targets: ["SharedKit"]),
    ],
    targets: [
        .target(name: "SharedKit"),
        .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"]),
    ]
)
