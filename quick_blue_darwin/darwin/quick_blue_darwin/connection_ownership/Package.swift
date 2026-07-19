// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "QuickBlueConnectionOwnership",
    products: [
        .library(
            name: "QuickBlueConnectionOwnership",
            targets: ["QuickBlueConnectionOwnership"]
        ),
    ],
    targets: [
        .target(name: "QuickBlueConnectionOwnership"),
        .testTarget(
            name: "QuickBlueConnectionOwnershipTests",
            dependencies: ["QuickBlueConnectionOwnership"]
        ),
    ]
)
