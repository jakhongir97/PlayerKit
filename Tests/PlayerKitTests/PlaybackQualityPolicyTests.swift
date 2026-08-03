import XCTest
@testable import PlayerKit

@MainActor
final class PlaybackQualityPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlayerManager.shared.configurePlaybackQualityBitRates([])
        PlayerManager.shared.resetPlaybackQualitySelection()
        PlayerManager.shared.playbackQualityPolicy = .automatic
        PlayerManager.shared.tearDown()
    }

    override func tearDown() {
        PlayerManager.shared.configurePlaybackQualityBitRates([])
        PlayerManager.shared.resetPlaybackQualitySelection()
        PlayerManager.shared.playbackQualityPolicy = .automatic
        PlayerManager.shared.tearDown()
        super.tearDown()
    }

    func testCapRejectsValuesThatAVFoundationTreatsAsInvalidOrAutomatic() throws {
        XCTAssertNil(PlaybackQualityPolicy.capped(at: 0))
        XCTAssertNil(PlaybackQualityPolicy.capped(at: -1))
        XCTAssertNil(PlaybackQualityPolicy.capped(at: .nan))
        XCTAssertNil(PlaybackQualityPolicy.capped(at: .infinity))

        let policy = try XCTUnwrap(PlaybackQualityPolicy.capped(at: 2_000_000))
        XCTAssertEqual(policy.maximumBitRate, 2_000_000)
        XCTAssertNil(PlaybackQualityPolicy.automatic.maximumBitRate)
    }

    func testWrapperAppliesCapToCurrentAndReplacementItems() {
        let wrapper = AVPlayerWrapper()
        wrapper.setPreferredPeakBitRate(1_500_000)

        wrapper.load(url: fixtureURL("first"), lastPosition: nil)
        XCTAssertEqual(wrapper.currentItemPreferredPeakBitRate, 1_500_000)

        wrapper.load(url: fixtureURL("second"), lastPosition: nil)
        XCTAssertEqual(wrapper.currentItemPreferredPeakBitRate, 1_500_000)

        wrapper.setPreferredPeakBitRate(0)
        XCTAssertEqual(wrapper.currentItemPreferredPeakBitRate, 0)
    }

    func testManagerPolicySurvivesAVPlayerRecreation() throws {
        let manager = PlayerManager.shared
        manager.playbackQualityPolicy = try XCTUnwrap(
            PlaybackQualityPolicy.capped(at: 3_000_000)
        )

        manager.setPlayer(type: .avPlayer)
        var wrapper = try XCTUnwrap(manager.currentPlayer as? AVPlayerWrapper)
        XCTAssertEqual(wrapper.preferredPeakBitRate, 3_000_000)

        manager.load(
            playerItem: PlayerItem(title: "First", url: fixtureURL("manager-first"))
        )
        XCTAssertEqual(wrapper.currentItemPreferredPeakBitRate, 3_000_000)

        manager.resetPlayer()
        manager.setPlayer(type: .avPlayer)
        wrapper = try XCTUnwrap(manager.currentPlayer as? AVPlayerWrapper)
        XCTAssertEqual(wrapper.preferredPeakBitRate, 3_000_000)

        manager.load(
            playerItem: PlayerItem(title: "Second", url: fixtureURL("manager-second"))
        )
        XCTAssertEqual(wrapper.currentItemPreferredPeakBitRate, 3_000_000)

        manager.playbackQualityPolicy = .automatic
        XCTAssertEqual(wrapper.currentItemPreferredPeakBitRate, 0)
    }

    func testQualityPresetsSanitizeAndMapStandardTiers() {
        let manager = PlayerManager.shared
        manager.configurePlaybackQualityBitRates([
            6_000_000, 1_000_000, 3_000_000, 3_000_000, 0, -1, .nan, .infinity
        ])

        XCTAssertEqual(manager.availablePlaybackQualityPresets, PlaybackQualityPreset.allCases)
        XCTAssertEqual(manager.playbackQualityPolicy, .automatic)

        manager.selectPlaybackQualityPreset(.maximum)
        XCTAssertEqual(manager.playbackQualityPolicy.maximumBitRate, 6_000_000)

        manager.selectPlaybackQualityPreset(.optimal)
        XCTAssertEqual(manager.playbackQualityPolicy.maximumBitRate, 3_000_000)

        manager.selectPlaybackQualityPreset(.minimum)
        XCTAssertEqual(manager.playbackQualityPolicy.maximumBitRate, 1_000_000)

        manager.selectPlaybackQualityPreset(.automatic)
        XCTAssertNil(manager.playbackQualityPolicy.maximumBitRate)
    }

    func testSemanticQualityChoiceRemapsAcrossManifestsAndSingleVariant() {
        let manager = PlayerManager.shared
        manager.configurePlaybackQualityBitRates([1_000_000, 3_000_000, 6_000_000])
        manager.selectPlaybackQualityPreset(.minimum)
        XCTAssertEqual(manager.playbackQualityPolicy.maximumBitRate, 1_000_000)

        manager.configurePlaybackQualityBitRates([2_000_000])
        XCTAssertTrue(manager.availablePlaybackQualityPresets.isEmpty)
        XCTAssertEqual(manager.selectedPlaybackQualityPreset, .minimum)
        XCTAssertEqual(manager.playbackQualityPolicy, .automatic)

        manager.configurePlaybackQualityBitRates([8_000_000, 4_000_000, 2_000_000])
        XCTAssertEqual(manager.selectedPlaybackQualityPreset, .minimum)
        XCTAssertEqual(manager.playbackQualityPolicy.maximumBitRate, 2_000_000)

        manager.resetPlaybackQualitySelection()
        XCTAssertEqual(manager.selectedPlaybackQualityPreset, .automatic)
        XCTAssertEqual(manager.playbackQualityPolicy, .automatic)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/playerkit-\(name).m3u8")
    }
}
