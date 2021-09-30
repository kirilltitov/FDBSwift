// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FDBSwift",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "FDB", targets: ["FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        .systemLibrary(name: "CFDB", pkgConfig: "libfdb"),
        .target(
            name: "FDB",
            dependencies: [
                "CFDB",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "FDBTests",
            dependencies: ["FDB"]
        ),
    ]
)
