// swift-tools-version:6.4

import PackageDescription

let package = Package(
    name: "FDBSwift",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FDB", targets: ["FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
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
        .testTarget(
            name: "FDBTests",
            dependencies: ["FDB"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
