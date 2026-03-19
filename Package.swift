// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Periscope",
    platforms: [
        .macOS(.v15)  // Will change to macOS 26 when SDK is available; .v15 for now to bootstrap
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Periscope",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Periscope"
        ),
        .testTarget(
            name: "PeriscopeTests",
            dependencies: ["Periscope"],
            path: "Tests/PeriscopeTests"
        ),
    ]
)
