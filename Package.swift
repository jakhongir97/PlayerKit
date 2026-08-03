// swift-tools-version: 5.10
import Foundation
import PackageDescription

// Which VLCKit artifact to build against.
//
// This used to be decided by probing for `Frameworks/VLCKit.xcframework`, a
// path that `.gitignore` excludes. A manifest that reads untracked state is not
// reproducible: a stray checkout artefact silently changed the dependency graph,
// and `swift package resolve` could produce different results on two machines
// at the same commit.
//
// It is now an explicit opt-in. Unset — which is every clean checkout, every CI
// runner and every consumer — resolves the published artifact, so the graph is
// identical everywhere.
//
// VLCKit is intentionally linked on iOS only. The macOS backend uses a separate
// runtime-checked VLC.app integration, so adding an unused local macOS binary
// would only add signing, licensing, and attack surface.
let localVLCKitPath = "Frameworks/VLCKit.xcframework"
let wantsLocalVLCKit = ProcessInfo.processInfo.environment["PLAYERKIT_LOCAL_VLCKIT"] == "1"
let hasLocalVLCKit: Bool = {
    guard wantsLocalVLCKit else { return false }
    guard FileManager.default.fileExists(atPath: localVLCKitPath) else {
        // Fail loudly rather than silently falling back to the published
        // artifact, which would build a different package than was asked for.
        fatalError("PLAYERKIT_LOCAL_VLCKIT=1 but \(localVLCKitPath) is missing.")
    }
    return true
}()

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
            url: "https://dl.google.com/dl/chromecast/sdk/ios/GoogleCastSDK-ios-4.8.4_dynamic.zip",
            checksum: "c9c3a794e8585198b59c6bb7da5418a3194ffa1ffa6f9a1cbdf4dc0ea26dc6cf"
        ),
        .target(
            name: "PlayerKit",
            dependencies: [
                .target(
                    name: "VLCKit",
                    condition: .when(platforms: [.iOS])
                ),
                .target(name: "GoogleCast", condition: .when(platforms: [.iOS])),
            ],
            path: "Sources/PlayerKit",
            resources: [
                .process("Resources")
            ],
            // Keep complete checking enabled for Swift 5.10 consumers while CI
            // also compiles this target in Swift 6 language mode. The package
            // itself stays in Swift 5 mode so the documented Xcode 15.3 minimum
            // remains usable.
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
