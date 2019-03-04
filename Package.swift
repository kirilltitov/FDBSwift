// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "FDBSwift",
    products: [
        .library(name: "FDB", targets: ["FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", .upToNextMajor(from: "1.9.0")),
    ],
    targets: [
        .systemLibrary(name: "CFDB", pkgConfig: "libfdb"),
        .target(name: "FDB", dependencies: ["CFDB", "NIO"]),
        .testTarget(name: "FDBTests", dependencies: ["FDB"]),
    ]
)
