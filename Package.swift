// swift-tools-version: 5.10
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
            path: "./Frameworks/VLCKit.xcframework"
        ),
        .binaryTarget(
            name: "GoogleCast",  // Update to reference GoogleCast
            path: "./Frameworks/GoogleCast.xcframework"  // Correct path to GoogleCast.xcframework
        ),
        .target(
            name: "PlayerKit",
            dependencies: ["VLCKit", "GoogleCast"],  // Add GoogleCast as a dependency
            path: "Sources",
            resources: [.process("Resources/Assets.xcassets")]
        ),
        .testTarget(
            name: "PlayerKitTests",
            dependencies: ["PlayerKit"]
        ),
    ]
)

