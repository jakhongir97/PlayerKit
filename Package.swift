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
            url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.3/VLCKit.xcframework.zip",
            checksum: "8f9989c70697ab64c378862c1d8f5fa696bb853db7c6294eb113b69e6140fed3"
        ),
        .binaryTarget(
            name: "GoogleCast",
            url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.3/GoogleCast.xcframework.zip",
            checksum: "64a2e1bf3e92bbe82e105cda874a00731406593b13d5112ccf39a8ea53477edd"
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

