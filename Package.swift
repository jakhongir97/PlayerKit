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
            url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.7/VLCKit.xcframework.zip",
            checksum: "2bb6de2ccd80a972cec24f19a2e1ecd3829eb87c6ea972cb39ca8c7c3968d997"
        ),
        .binaryTarget(
            name: "GoogleCast",
            url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.7/GoogleCast.xcframework.zip",
            checksum: "21090c27acb00c9576e44c4af084c473509ba6b9dd494d23b53f5390b0bcad91"
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

