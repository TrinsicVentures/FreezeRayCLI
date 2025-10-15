// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "freezeray",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "freezeray", targets: ["freezeray-bin"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-syntax", from: "600.0.0"),
        .package(url: "https://github.com/tuist/XcodeProj", from: "8.0.0"),
    ],
    targets: [
        // CLI library (testable)
        .target(
            name: "freezeray-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        // CLI executable (thin wrapper)
        .executableTarget(
            name: "freezeray-bin",
            dependencies: ["freezeray-cli"]
        ),
        // CLI tests
        .testTarget(
            name: "FreezeRayCLITests",
            dependencies: ["freezeray-cli"]
        )
    ]
)
