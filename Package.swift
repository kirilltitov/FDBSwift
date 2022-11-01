// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "FDBSwift",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "FDB", targets: ["FDB"]),
        .library(name: "FDBEntity", targets: ["FDBEntity"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1711-Games/LGN-Log.git", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/kirilltitov/MessagePack.git", .upToNextMajor(from: "2.0.0")),
    ],
    targets: [
        .systemLibrary(name: "CFDB", pkgConfig: "libfdb"),
        .target(
            name: "FDB",
            dependencies: [
                "CFDB",
                "Helpers",
                .product(name: "LGNLog", package: "LGN-Log"),
            ]
        ),
        .target(
            name: "FDBEntity",
            dependencies: [
                "FDB",
                "Helpers",
                "MessagePack",
                .product(name: "LGNLog", package: "LGN-Log"),
            ]
        ),
        .target(
            name: "Helpers",
            dependencies: []
        ),
        .testTarget(name: "FDBTests", dependencies: ["FDB"]),
        .testTarget(name: "FDBEntityTests", dependencies: ["FDB", "FDBEntity"]),
    ]
)
