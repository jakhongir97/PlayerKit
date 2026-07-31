// swift-tools-version: 5.10
import Foundation
import PackageDescription

let localVLCKitPath = "Frameworks/VLCKit.xcframework"
let hasLocalVLCKit = FileManager.default.fileExists(atPath: localVLCKitPath)

let vlcBinaryTarget: Target = hasLocalVLCKit
    ? .binaryTarget(
        name: "VLCKit",
        path: localVLCKitPath
    )
    : .binaryTarget(
        name: "VLCKit",
        url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.7/VLCKit.xcframework.zip",
        checksum: "2bb6de2ccd80a972cec24f19a2e1ecd3829eb87c6ea972cb39ca8c7c3968d997"
    )

let package = Package(
    name: "PlayerKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PlayerKit", targets: ["PlayerKit"]),
    ],
    dependencies: [],
    targets: [
        vlcBinaryTarget,
        .binaryTarget(
            name: "GoogleCast",
            url: "https://github.com/jakhongir97/PlayerKit/releases/download/1.0.7/GoogleCast.xcframework.zip",
            checksum: "21090c27acb00c9576e44c4af084c473509ba6b9dd494d23b53f5390b0bcad91"
        ),
        .target(
            name: "PlayerKit",
            dependencies: [
                .target(
                    name: "VLCKit",
                    condition: .when(platforms: hasLocalVLCKit ? [.iOS, .macOS] : [.iOS])
                ),
                .target(name: "GoogleCast", condition: .when(platforms: [.iOS])),
            ],
            path: "Sources/PlayerKit",
            resources: [
                .process("Resources")
            ],
            // Turns on complete concurrency checking as WARNINGS, to stop the
            // diagnostic count growing while the @MainActor migration is
            // scheduled. The package is in Swift 5 language mode — there is no
            // swiftLanguageVersions setting and swift-tools-version is 5.10 —
            // so these are warnings, not errors. Raising the tools version or
            // adding .v6 to swiftLanguageVersions would turn all ~291 of them
            // into build failures.
            //
            // swiftSettings apply to this target only and are not inherited by
            // anything that depends on PlayerKit, so a consumer sees no new
            // diagnostics of its own.
            //
            // Deliberately NOT .unsafeFlags: SwiftPM rejects a package that
            // uses them from any consumer depending on it by version or URL,
            // which would break iTV's build outright at graph-resolution time.
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "PlayerKitTests",
            dependencies: ["PlayerKit"]
        ),
    ]
)
