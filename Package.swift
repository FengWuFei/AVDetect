// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AVDetect",
    dependencies: [
        .package(url: "https://github.com/FengWuFei/SwiftFFmpeg.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.13.1"),
    ],
    targets: [
        .target(
            name: "AVDetect",
            dependencies: ["SwiftFFmpeg", "NIO"]),
        .testTarget(
            name: "AVDetectTests",
            dependencies: ["AVDetect"]),
    ]
)
