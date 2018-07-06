// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FDBSwift",
    products: [
        .library(name: "FDB", targets: ["FDB"]),
        .executable(name: "FDBTestDrive", targets: ["FDBTestDrive"])
    ],
    dependencies: [
        .package(url: "../CFDBSwift", .branch("master")),
    ],
    targets: [
        .target(name: "FDB", dependencies: ["CFDB"]),
        .target(name: "FDBTestDrive", dependencies: ["CFDB", "FDB"]),
        .testTarget(name: "FDBTests", dependencies: ["FDB"]),
    ]
)
