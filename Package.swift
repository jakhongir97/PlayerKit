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
// Note what this does NOT currently do. The published VLCKit.xcframework ships
// `ios-arm64` and `ios-arm64_x86_64-simulator` only, with no macOS slice, so
// `canImport(VLCKit)` is false on macOS either way and `DesktopVLCPlayerWrapper`
// (`#if os(macOS) && !canImport(VLCKit)`) compiles in both configurations —
// verified by finding DesktopVLCPlayerWrapper.swift.o in both builds. The
// hazard is latent rather than active: drop in a locally built xcframework that
// *does* carry a macOS slice and the macOS backend flips, taking the public
// `VLCPlayerWrapper` typealias with it.
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
