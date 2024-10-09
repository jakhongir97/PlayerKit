// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlayerKit",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "PlayerKit", targets: ["PlayerKit"]),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "VLCKit",
            path: "./Frameworks/VLCKit.xcframework" // The path to your XCFramework
        ),
        .target(
            name: "PlayerKit",
            dependencies: ["VLCKit"],
            path: "Sources"
        ),
        .testTarget(
            name: "PlayerKitTests",
            dependencies: ["PlayerKit"]
        ),
    ]
)

