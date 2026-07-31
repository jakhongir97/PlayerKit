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

    // MARK: - Live timeline: one clamping path

    /// A live/DVR HLS timeline: `duration` is 0 because AVFoundation reports an
    /// indefinite duration, and the only usable bounds are the backend's
    /// seekable window.
    private static let liveWindow: ClosedRange<Double> = 3600...7200

    private func makeLiveManager(
        currentTime: Double
    ) -> (PlayerManager, LiveTimelineMockPlayer) {
        let manager = PlayerManager.shared
        manager.resetPlayer()

        let player = LiveTimelineMockPlayer()
        player.seekableTimeWindow = Self.liveWindow
        player.currentTime = currentTime
        player.duration = 0

        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.duration = 0
        manager.currentTime = currentTime

        return (manager, player)
    }

    /// The slider binds its range to `seekableRange`. It used to bind
    /// `0...max(duration, 0.01)`, which on live is `0...0.01` — every drag
    /// resolved to the same position and the control was decorative.
    func testSeekableRangeIsTheLiveWindowWhenDurationIsIndefinite() {
        let (manager, player) = makeLiveManager(currentTime: 5000)
        defer { manager.tearDown() }
        withExtendedLifetime(player) {
            XCTAssertEqual(manager.duration, 0)
            XCTAssertEqual(manager.seekableRange, Self.liveWindow)
            // The range the old code would have produced.
            XCTAssertNotEqual(manager.seekableRange, 0...0.01)
        }
    }

    /// Entry point 1 — a slider drag calls `seek(to:)` directly. A target
    /// inside the DVR window must land exactly, not be clamped to zero.
    func testSeekLandsInsideLiveWindow() {
        let (manager, player) = makeLiveManager(currentTime: 5000)
        defer { manager.tearDown() }
        withExtendedLifetime(player) {
            var observed: Bool?
            manager.seek(to: 6000) { observed = $0 }

            XCTAssertEqual(observed, true)
            XCTAssertEqual(manager.currentTime, 6000)
            XCTAssertEqual(player.currentTime, 6000)
        }
    }

    /// A target below the window's start clamps to the start, not to zero.
    func testSeekBelowLiveWindowClampsToWindowStart() {
        let (manager, player) = makeLiveManager(currentTime: 5000)
        defer { manager.tearDown() }
        withExtendedLifetime(player) {
            manager.seek(to: 10)

            XCTAssertEqual(manager.currentTime, Self.liveWindow.lowerBound)
        }
    }

    /// Entry point 2 — `scrubForward`/`scrubBackward` used to call
    /// `playbackManager?.scrub…` straight through to the backend, which seeks
    /// to `currentTime ± seconds` with no knowledge of the seekable window.
    /// Past the live edge that asked for a position that does not exist.
    func testScrubForwardClampsToLiveWindowEnd() {
        let (manager, player) = makeLiveManager(currentTime: 7190)
        defer { manager.tearDown() }
        withExtendedLifetime(player) {
            manager.scrubForward(by: 60)

            XCTAssertEqual(manager.currentTime, Self.liveWindow.upperBound)
            XCTAssertEqual(player.currentTime, Self.liveWindow.upperBound)
            // The unclamped position the old pass-through would have produced.
            XCTAssertNotEqual(player.currentTime, 7250)
        }
    }

    /// The mirror case: scrubbing back past the start of the DVR window.
    func testScrubBackwardClampsToLiveWindowStart() {
        let (manager, player) = makeLiveManager(currentTime: 3610)
        defer { manager.tearDown() }
        withExtendedLifetime(player) {
            manager.scrubBackward(by: 60)

            XCTAssertEqual(manager.currentTime, Self.liveWindow.lowerBound)
            XCTAssertNotEqual(player.currentTime, 3550)
        }
    }

    /// Scrubbing within the window is unaffected — the clamp must not change
    /// ordinary behaviour.
    func testScrubForwardWithinLiveWindowMovesByTheFullAmount() {
        let (manager, player) = makeLiveManager(currentTime: 5000)
        defer { manager.tearDown() }
        withExtendedLifetime(player) {
            manager.scrubForward(by: 30)

            XCTAssertEqual(manager.currentTime, 5030)
        }
    }

    /// Entry point 3 — the double-tap skip. `GestureManager` clamped with
    /// `min(duration, …)`, so on live (`duration == 0`) every skip resolved to
    /// 0 and the double-tap jumped to the start of the stream.
    func testDoubleTapSkipForwardStaysInsideLiveWindow() {
        let gestureManager = GestureManager()
        gestureManager.currentTimeProvider = { 5000 }
        gestureManager.seekableRangeProvider = { Self.liveWindow }

        var seekTargets: [Double] = []
        gestureManager.onSeek = { seekTargets.append($0) }

        let size = CGSize(width: 400, height: 200)
        let rightSide = CGPoint(x: 300, y: 100)
        gestureManager.handleTap(at: rightSide, in: size)
        gestureManager.handleTap(at: rightSide, in: size)

        XCTAssertEqual(seekTargets, [5010])
    }

    func testDoubleTapSkipBackwardClampsToLiveWindowStartNotZero() {
        let gestureManager = GestureManager()
        gestureManager.currentTimeProvider = { 3605 }
        gestureManager.seekableRangeProvider = { Self.liveWindow }

        var seekTargets: [Double] = []
        gestureManager.onSeek = { seekTargets.append($0) }

        let size = CGSize(width: 400, height: 200)
        let leftSide = CGPoint(x: 100, y: 100)
        gestureManager.handleTap(at: leftSide, in: size)
        gestureManager.handleTap(at: leftSide, in: size)

        // 3605 - 10 = 3595, below the window. The old clamp produced 0.
        XCTAssertEqual(seekTargets, [Self.liveWindow.lowerBound])
        XCTAssertNotEqual(seekTargets.first, 0)
    }

    /// With no seekable window at all the skip is dropped rather than sent to
    /// an arbitrary position.
    func testDoubleTapSkipIsDroppedWithoutASeekableRange() {
        let gestureManager = GestureManager()
        gestureManager.currentTimeProvider = { 5000 }
        gestureManager.seekableRangeProvider = { nil }

        var seekTargets: [Double] = []
        gestureManager.onSeek = { seekTargets.append($0) }

        let size = CGSize(width: 400, height: 200)
        let rightSide = CGPoint(x: 300, y: 100)
        gestureManager.handleTap(at: rightSide, in: size)
        gestureManager.handleTap(at: rightSide, in: size)

        XCTAssertTrue(seekTargets.isEmpty)
    }

    /// VOD is unchanged: the seekable range is `0...duration`, and all three
    /// entry points clamp to it exactly as they did before.
    func testVODTimelineStillClampsToDuration() {
        let manager = PlayerManager.shared
        manager.resetPlayer()
        defer { manager.tearDown() }

        let player = LiveTimelineMockPlayer()
        player.seekableTimeWindow = nil
        player.duration = 600
        player.currentTime = 590
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.duration = 600
        manager.currentTime = 590

        withExtendedLifetime(player) {
            XCTAssertEqual(manager.seekableRange, 0...600)

            manager.scrubForward(by: 60)
            XCTAssertEqual(manager.currentTime, 600)

            manager.seek(to: -10)
            XCTAssertEqual(manager.currentTime, 0)
        }
    }

    // MARK: - Dub language selection

    /// The built-in Start button forced the target language to Uzbek, which
    /// silently defeated `setDubLanguage(code:)`.
    @MainActor
    func testSetDubLanguageIsNotOverriddenByConfigurationDefault() throws {
        try XCTSkipUnless(
            PlayerKitFeatureFlags.isDubberEnabled,
            "Dubber is disabled in this build; see PlayerKitFeatureFlags."
        )
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        manager.configureDubber(
            DubberConfiguration(baseURL: URL(string: "https://dubber.test/api")!)
        )
        manager.setDubLanguage(code: "en")

        XCTAssertEqual(manager.selectedDubLanguageCode, "en")
    }
}

/// A backend that can report a live/DVR shaped timeline.
///
/// The distinguishing feature is that `duration` and `seekableTimeWindow` are
/// independent: live HLS reports `duration == 0` while still exposing a
/// seekable DVR window, and that combination is what every clamping site used
/// to get wrong.
private final class LiveTimelineMockPlayer: PlayerProtocol, PlayerSeekWindowReporting {
    var isPlaying = false
    var playbackSpeed: Float = 1
    var currentTime: Double = 0
    var duration: Double = 0
    var bufferedDuration: Double = 0
    var isBuffering = false
    var availableAudioTracks: [TrackInfo] = []
    var availableSubtitles: [TrackInfo] = []
    var currentAudioTrack: TrackInfo?
    var currentSubtitleTrack: TrackInfo?

    var seekableTimeWindow: ClosedRange<Double>?
    /// Every position the backend was asked to seek to, in order, so a test can
    /// assert that a clamp happened before the request rather than after.
    private(set) var seekRequests: [Double] = []

    func canSeekWithinCurrentWindow(to time: Double, tolerance: Double) -> Bool {
        guard let seekableTimeWindow else { return false }
        return time + tolerance >= seekableTimeWindow.lowerBound
            && time <= seekableTimeWindow.upperBound + tolerance
    }

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }

    func seek(to time: Double, completion: ((Bool) -> Void)?) {
        seekRequests.append(time)
        currentTime = time
        completion?(true)
    }

    /// Deliberately unclamped, matching the real backends: they seek to
    /// `currentTime ± seconds` with no knowledge of the seekable window. That
    /// is precisely why `PlayerManager` must not call these directly.
    func scrubForward(by seconds: TimeInterval) { currentTime += seconds }
    func scrubBackward(by seconds: TimeInterval) { currentTime -= seconds }

    func selectAudioTrack(withID id: String) {
        currentAudioTrack = availableAudioTracks.first(where: { $0.id == id })
    }

    func selectSubtitle(withID id: String?) {
        currentSubtitleTrack = availableSubtitles.first(where: { $0.id == id })
    }

    func load(url: URL, lastPosition: Double?) {
        currentTime = lastPosition ?? 0
    }

    func getPlayerView() -> PKView { PlayerKit.AVPlayerView() }

    func setupPiP() {}
    func startPiP() {}
    func stopPiP() {}
    func handlePinchGesture(scale: CGFloat) {}
    func setGravityToDefault() {}
    func setGravityToFill() {}

    func fetchStreamingInfo() -> StreamingInfo { .placeholder }
}
