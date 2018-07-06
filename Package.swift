// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "FDBSwift",
    products: [
        .library(name: "FDB", targets: ["FDB"]),
        .executable(name: "FDBTestDrive", targets: ["FDBTestDrive"])
    ],
    dependencies: [
        .package(url: "https://github.com/kirilltitov/CFDBSwift", .branch("master")),
    ],
    targets: [
        .target(name: "FDB", dependencies: ["CFDBSwift"]),
        .target(name: "FDBTestDrive", dependencies: ["FDB"]),
        .testTarget(name: "FDBTests", dependencies: ["FDB"]),
    ]
)
