#if os(macOS)
import AVFoundation
import XCTest
@testable import PlayerKit

final class PlaybackHealthPrivacyTests: XCTestCase {
    func testOpaqueAssetIdentifierIsNormalizedBeforeMonitorRetention() {
        let wrapper = AVPlayerWrapper()
        defer { wrapper.stop() }
        let rawIdentifier = "https://media.example/asset.m3u8?token=secret"

        wrapper.load(
            url: URL(string: "https://example.invalid/privacy.m3u8")!,
            playbackHealthAssetIdentifier: rawIdentifier,
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )

        let retainedIdentifier = wrapper.activePlaybackHealthAssetIdentifier
        XCTAssertNotEqual(retainedIdentifier, rawIdentifier)
        XCTAssertTrue(retainedIdentifier?.hasPrefix("sha256:") == true)
        XCTAssertFalse(
            wrapper.fetchPlaybackDiagnostics(
                monitoringEnabled: true,
                recentHealthEvents: []
            ).report().contains(rawIdentifier)
        )
    }

    func testNumericAndCanonicalHashedIdentifiersRemainStable() {
        let wrapper = AVPlayerWrapper()
        defer { wrapper.stop() }
        let canonicalHash = "sha256:" + String(repeating: "a", count: 64)

        wrapper.load(
            url: URL(string: "https://example.invalid/privacy.m3u8")!,
            playbackHealthAssetIdentifier: "42",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )
        XCTAssertEqual(wrapper.activePlaybackHealthAssetIdentifier, "42")

        wrapper.load(
            url: URL(string: "https://example.invalid/privacy.m3u8")!,
            playbackHealthAssetIdentifier: canonicalHash.uppercased(),
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )
        XCTAssertEqual(wrapper.activePlaybackHealthAssetIdentifier, canonicalHash)
    }

    func testOversizedAssetIdentifierIsRejected() {
        let wrapper = AVPlayerWrapper()
        defer { wrapper.stop() }

        wrapper.load(
            url: URL(string: "https://example.invalid/privacy.m3u8")!,
            playbackHealthAssetIdentifier: String(repeating: "x", count: 4_097),
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )

        XCTAssertNil(wrapper.activePlaybackHealthAssetIdentifier)
    }

    func testURLAssetFingerprintIgnoresQueryAndFragment() {
        let wrapper = AVPlayerWrapper()
        defer { wrapper.stop() }
        let playbackURL = URL(string: "https://example.invalid/privacy.m3u8")!

        wrapper.load(
            url: playbackURL,
            playbackHealthAssetIdentifier:
                "https://MEDIA.example:8443/asset%20one.m3u8?token=alpha#first",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )
        let first = wrapper.activePlaybackHealthAssetIdentifier

        wrapper.load(
            url: playbackURL,
            playbackHealthAssetIdentifier:
                "https://media.example:8443/asset%20one.m3u8?token=beta#second",
            playbackHealthMonitoringEnabled: true,
            playbackHealthMonitoringEligible: true
        )

        XCTAssertEqual(wrapper.activePlaybackHealthAssetIdentifier, first)
    }

    func testLanguageSanitizerCanonicalizesKnownTagsAndRejectsTokenText() {
        let wrapper = AVPlayerWrapper()

        XCTAssertEqual(wrapper.sanitizedPlaybackHealthLanguage("eng_US"), "en-US")
        XCTAssertEqual(wrapper.sanitizedPlaybackHealthLanguage("uz-Latn"), "uz-Latn")
        XCTAssertNil(wrapper.sanitizedPlaybackHealthLanguage("Bearer_secret_token"))
        XCTAssertNil(wrapper.sanitizedPlaybackHealthLanguage("abc"))
    }
}
#endif
