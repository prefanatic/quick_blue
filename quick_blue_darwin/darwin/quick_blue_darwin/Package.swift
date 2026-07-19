// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "quick_blue_darwin",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "quick-blue-darwin", targets: ["quick_blue_darwin"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(
            name: "QuickBlueConnectionOwnership",
            path: "connection_ownership"
        ),
    ],
    targets: [
        .target(
            name: "quick_blue_darwin",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(
                    name: "QuickBlueConnectionOwnership",
                    package: "QuickBlueConnectionOwnership"
                ),
            ],
            cSettings: [
                .headerSearchPath("include/quick_blue_darwin"),
            ]
        ),
    ]
)
