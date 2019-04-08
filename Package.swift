// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "FDBSwift",
    products: [
        .library(name: "FDB", targets: ["FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/kirilltitov/swift-log.git", .upToNextMajor(from: "0.0.0")),
    ],
    targets: [
        .systemLibrary(name: "CFDB", pkgConfig: "libfdb"),
        .target(name: "FDB", dependencies: ["CFDB", "NIO", "Logging"]),
        .testTarget(name: "FDBTests", dependencies: ["FDB"]),
    ]
)
