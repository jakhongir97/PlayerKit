import XCTest
@testable import PlayerKit

/// Verifies that the Dubber integration is fully inert while
/// `PlayerKitFeatureFlags.isDubberEnabled` is `false`.
///
/// The implementation is still present in the target, so these tests are what
/// guarantee it cannot be reached — no UI, no session, no network, no tasks.
@MainActor
final class DubberDisabledTests: XCTestCase {

    private var manager: PlayerManager { .shared }

    override func tearDown() {
        manager.tearDown()
        super.tearDown()
    }

    func testFeatureFlagIsOff() {
        XCTAssertFalse(PlayerKitFeatureFlags.isDubberEnabled)
    }

    /// `configureDubber` is the only writer of the configuration, and every
    /// network call in DubberClient requires one.
    func testConfigureDubberDoesNotArmTheIntegration() {
        manager.configureDubber(
            DubberConfiguration(baseURL: URL(string: "https://dubber.test/api")!)
        )

        XCTAssertFalse(manager.isDubberEnabled)
        XCTAssertFalse(manager.showsDubberControls)
        XCTAssertTrue(manager.availableDubLanguages.isEmpty)
        XCTAssertTrue(manager.availableDubSourceLanguages.isEmpty)
    }

    /// The player chrome gates every Dubber affordance on `showsDubberControls`,
    /// which folds in the feature flag.
    func testDubberControlsAreNeverShown() {
        manager.configureDubber(
            DubberConfiguration(baseURL: URL(string: "https://dubber.test/api")!)
        )
        XCTAssertFalse(manager.showsDubberControls)
    }

    /// `startDubbedPlayback` is the sole initiator of a Dubber session and of
    /// the polling / SSE / watchdog tasks. It must return without creating one
    /// and without contacting the network.
    func testStartDubbedPlaybackCreatesNoSession() async {
        manager.configureDubber(
            DubberConfiguration(baseURL: URL(string: "https://dubber.test/api")!)
        )
        manager.load(
            playerItem: PlayerItem(
                title: "Fixture",
                url: URL(string: "https://example.com/index.m3u8")!
            )
        )

        await manager.startDubbedPlayback()

        XCTAssertNil(manager.dubSessionID)
        XCTAssertFalse(manager.isDubLoading)
        XCTAssertFalse(manager.isDubbedPlaybackActive)
        XCTAssertNil(manager.dubStatus)
    }

    /// Disabled means silent, not failing: a host that still calls the dub API
    /// should not have an error pushed at its users.
    func testDisabledDubAPIDoesNotSurfaceAnError() async {
        manager.load(
            playerItem: PlayerItem(
                title: "Fixture",
                url: URL(string: "https://example.com/index.m3u8")!
            )
        )

        await manager.startDubbedPlayback()

        XCTAssertNil(manager.lastError)
    }

    func testLanguageSelectionIsInert() {
        manager.configureDubber(
            DubberConfiguration(baseURL: URL(string: "https://dubber.test/api")!)
        )

        let originalTarget = manager.selectedDubLanguageCode
        let originalSource = manager.selectedDubSourceLanguageCode

        manager.setDubLanguage(code: "en")
        manager.setDubSourceLanguage(code: "ru")

        XCTAssertEqual(manager.selectedDubLanguageCode, originalTarget)
        XCTAssertEqual(manager.selectedDubSourceLanguageCode, originalSource)
    }

    func testStopDubbingIsInert() {
        manager.stopDubbingAndReturnToOriginalAudio()

        XCTAssertNil(manager.dubSessionID)
        XCTAssertFalse(manager.isDubbedPlaybackActive)
        XCTAssertNil(manager.lastError)
    }

    /// Ordinary playback must be entirely unaffected by the dub machinery
    /// sitting dormant in the target.
    func testNormalPlaybackIsUnaffected() {
        let item = PlayerItem(
            title: "Fixture",
            url: URL(string: "https://example.com/index.m3u8")!
        )
        manager.load(playerItem: item)

        XCTAssertEqual(manager.playerItem?.url, item.url)
        XCTAssertNil(manager.dubSessionID)
        XCTAssertNil(manager.lastError)
    }
}
