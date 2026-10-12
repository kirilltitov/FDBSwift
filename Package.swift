// swift-tools-version:6.4

import PackageDescription

let package = Package(
    name: "FDBSwift",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FDB", targets: ["FDB"]),
        .library(name: "FDBEntity", targets: ["FDBEntity"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        // Used by FDBEntity
        .package(url: "https://github.com/kirilltitov/MessagePack.git", from: "2.0.0"),
    ],
    targets: [
        .systemLibrary(name: "CFDB", pkgConfig: "libfdb"),
        .target(
            name: "FDB",
            dependencies: [
                "CFDB",
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .target(
            name: "FDBEntity",
            dependencies: [
                "FDB",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MessagePack", package: "MessagePack"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .executableTarget(
            name: "FDBBindingTester",
            dependencies: ["FDB"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "FDBTests",
            dependencies: ["FDB"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "FDBEntityTests",
            dependencies: ["FDBEntity"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
