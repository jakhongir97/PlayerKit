import AVFoundation
import XCTest
@testable import PlayerKit

/// Regression coverage for defects found in the full-codebase audit.
///
/// Each test names the behaviour that was wrong before, so a future change that
/// reintroduces it fails here rather than in a user's hands.
final class AuditRegressionTests: XCTestCase {

    // MARK: - Time formatting

    /// Previously the UI formatter allowed only `[.minute, .second]`, so a
    /// 2h02m film rendered as "122:05" instead of "2:02:05".
    func testTimeStringIncludesHoursForLongContent() {
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: 7325), "2:02:05")
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: 3600), "1:00:00")
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: 36000), "10:00:00")
    }

    func testTimeStringPadsMinutesAndSecondsBelowAnHour() {
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: 0), "00:00")
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: 59), "00:59")
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: 3599), "59:59")
    }

    /// Non-finite and negative values used to reach `DateComponentsFormatter`
    /// directly and could surface as an empty string in the UI.
    func testTimeStringSanitizesNonFiniteAndNegativeInput() {
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: .nan), "00:00")
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: .infinity), "00:00")
        XCTAssertEqual(PlayerKitTimeFormatter.string(from: -42), "00:00")
    }

    /// The `asTimeString` extension is what the sliders actually call; it must
    /// agree with the formatter rather than reimplementing it.
    func testAsTimeStringExtensionMatchesFormatter() {
        XCTAssertEqual(Double(7325).asTimeString(style: .positional), "2:02:05")
    }

    // MARK: - Episode queue bounds

    /// `loadEpisodes(currentIndex:)` stored the caller's index verbatim. An
    /// out-of-range value survived, and the next `playPrevious()` stepped it
    /// into an unguarded array subscript and trapped.
    func testLoadEpisodesClampsOutOfRangeIndex() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        let items = (0 ..< 3).map { index in
            PlayerItem(title: "Episode \(index)", url: URL(string: "https://example.com/\(index).m3u8")!)
        }

        manager.loadEpisodes(playerItems: items, currentIndex: 99)
        XCTAssertEqual(manager.currentPlayerItemIndex, 2)

        manager.loadEpisodes(playerItems: items, currentIndex: -5)
        XCTAssertEqual(manager.currentPlayerItemIndex, 0)
    }

    /// The concrete crash path: an out-of-range index followed by a navigation
    /// action. Reaching the end of this test at all is the assertion.
    func testEpisodeNavigationAfterOutOfRangeIndexDoesNotTrap() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        let items = (0 ..< 3).map { index in
            PlayerItem(title: "Episode \(index)", url: URL(string: "https://example.com/\(index).m3u8")!)
        }

        manager.loadEpisodes(playerItems: items, currentIndex: 99)
        manager.playPrevious()
        manager.playNext()

        XCTAssertTrue(manager.playerItems.indices.contains(manager.currentPlayerItemIndex))
    }

    func testLoadEpisodesWithEmptyQueueLeavesIndexAtZero() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        manager.loadEpisodes(playerItems: [], currentIndex: 7)
        XCTAssertEqual(manager.currentPlayerItemIndex, 0)
    }

    // MARK: - Playback speed

    /// Speed was read back from `AVPlayer.rate`, which is 0 while paused, so the
    /// selection was discarded on every pause and reset to 1× on resume.
    func testPlaybackSpeedSurvivesWithoutAnActivePlayer() {
        let wrapper = AVPlayerWrapper()
        wrapper.playbackSpeed = 1.5
        XCTAssertEqual(wrapper.playbackSpeed, 1.5, accuracy: 0.0001)
    }

    func testPlaybackSpeedRejectsNonPositiveAndNonFiniteRates() {
        let wrapper = AVPlayerWrapper()

        wrapper.playbackSpeed = 0
        XCTAssertEqual(wrapper.playbackSpeed, 1.0, accuracy: 0.0001)

        wrapper.playbackSpeed = 2.0
        wrapper.playbackSpeed = -1
        XCTAssertEqual(wrapper.playbackSpeed, 1.0, accuracy: 0.0001)

        wrapper.playbackSpeed = .nan
        XCTAssertEqual(wrapper.playbackSpeed, 1.0, accuracy: 0.0001)
    }

    // MARK: - Seek coalescing

    /// Superseded seeks used to have their completion handler overwritten, so
    /// callers waiting on them were never called back at all.
    func testCoalescedSeeksNotifyEverySupersededCaller() {
        let player = SmoothPlayer()
        let expectation = expectation(description: "all seek completions run")
        expectation.expectedFulfillmentCount = 3

        for offset in 0 ..< 3 {
            player.seek(to: CMTime(seconds: Double(offset), preferredTimescale: 600)) { _ in
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    /// Teardown must fail outstanding seeks rather than leave their callers
    /// waiting on a completion that can no longer arrive.
    func testCancelCoalescedSeeksFailsOutstandingCallers() {
        let player = SmoothPlayer()
        let expectation = expectation(description: "cancelled seek reports failure")

        player.seek(to: CMTime(seconds: 30, preferredTimescale: 600)) { finished in
            XCTAssertFalse(finished)
            expectation.fulfill()
        }
        player.cancelCoalescedSeeks()

        wait(for: [expectation], timeout: 5)
    }

    // MARK: - Live / indefinite duration

    /// `duration` is 0 for live HLS, and the old `guard duration != 0` made
    /// every seek on a live stream a silent no-op. With no player attached
    /// there is no seekable window either, so the range is genuinely nil — but
    /// the seek must report failure through the completion rather than hang.
    func testSeekWithoutSeekableRangeReportsFailure() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        manager.resetPlayer()

        var observed: Bool?
        manager.seek(to: 42) { success in
            observed = success
        }

        XCTAssertEqual(observed, false)
        XCTAssertNil(manager.seekableRange)
    }

    // MARK: - Dub language selection

    /// The built-in Start button forced the target language to Uzbek, which
    /// silently defeated `setDubLanguage(code:)`.
    @MainActor
    func testSetDubLanguageIsNotOverriddenByConfigurationDefault() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        manager.configureDubber(
            DubberConfiguration(baseURL: URL(string: "https://dubber.test/api")!)
        )
        manager.setDubLanguage(code: "en")

        XCTAssertEqual(manager.selectedDubLanguageCode, "en")
    }
}
