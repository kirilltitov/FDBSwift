// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "FDBSwift",
    products: [
        .library(name: "FDB", targets: ["FDB"]),
        .executable(name: "FDBTestDrive", targets: ["FDBTestDrive"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        .systemLibrary(name: "CFDB", pkgConfig: "libfdb"),
        .target(
            name: "FDB",
            dependencies: ["CFDB", "NIO", "Logging"],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-enable-experimental-concurrency"])]
        ),
        .target(
            name: "FDBTestDrive",
            dependencies: ["FDB"],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-enable-experimental-concurrency"])]
        ),
//        .testTarget(
//            name: "FDBTests",
//            dependencies: ["FDB"],
//            swiftSettings: [.unsafeFlags(["-Xfrontend", "-enable-experimental-concurrency"])]
//        ),
    ]
)
