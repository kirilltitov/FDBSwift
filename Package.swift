// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FDBSwift",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "FDB", targets: ["FDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1711-Games/LGN-Log.git", .upToNextMinor(from: "0.3.0")),
    ],
    targets: [
        .systemLibrary(name: "CFDB", pkgConfig: "libfdb"),
        .target(
            name: "FDB",
            dependencies: [
                "CFDB",
                .product(name: "LGNLog", package: "LGN-Log"),
            ]
        ),
        .testTarget(
            name: "FDBTests",
            dependencies: ["FDB"]
        ),
    ]
)
