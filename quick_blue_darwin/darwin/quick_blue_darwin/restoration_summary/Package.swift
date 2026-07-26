// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "QuickBlueRestorationSummary",
    products: [
        .library(
            name: "QuickBlueRestorationSummary",
            targets: ["QuickBlueRestorationSummary"]
        ),
    ],
    targets: [
        .target(name: "QuickBlueRestorationSummary"),
        .testTarget(
            name: "QuickBlueRestorationSummaryTests",
            dependencies: ["QuickBlueRestorationSummary"]
        ),
    ]
)
