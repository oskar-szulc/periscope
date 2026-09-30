// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Periscope",
    platforms: [
        .macOS(.v26)
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
            path: "Sources/Periscope",
            // Ours only: -Xswiftc -warnings-as-errors would also fail on
            // swift-argument-parser's own deprecation warnings.
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "PeriscopeTests",
            dependencies: ["Periscope"],
            path: "Tests/PeriscopeTests",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
