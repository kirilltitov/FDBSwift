// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "FDBSwift",
    products: [
        .library(name: "FDB", targets: ["FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kirilltitov/CFDBSwift", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio", .upToNextMajor(from: "1.9.0")),
    ],
    targets: [
        .target(name: "FDB", dependencies: ["CFDBSwift", "NIO"]),
        .testTarget(name: "FDBTests", dependencies: ["FDB"]),
    ]
)
