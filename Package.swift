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
            url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.0/VLCKit.xcframework.zip",
            checksum: "008a221c89da2d43529eb4e2592d13440a01823d50359195494c8dfa2841d8d3"
        ),
        .binaryTarget(
            name: "GoogleCast",
            url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.0/GoogleCast.xcframework.zip",
            checksum: "dd6f57d4108a81dba2c0f32c412192c330f6508cf109d75aae02eb6f3284b1cb"
        ),
        .target(
            name: "PlayerKit",
            dependencies: ["VLCKit", "GoogleCast"],
            path: "Sources"
        ),
        .testTarget(
            name: "PlayerKitTests",
            dependencies: ["PlayerKit"]
        ),
    ]
)

