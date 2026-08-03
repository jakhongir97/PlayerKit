import AVFoundation
import XCTest
@testable import PlayerKit

@MainActor
final class BackendLifecycleRegressionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlayerManager.shared.tearDown()
    }

    override func tearDown() {
        PlayerManager.shared.autoplay = true
        PlayerManager.shared.isMuted = false
        PlayerManager.shared.isExternalPlaybackEnabled = false
        PlayerManager.shared.setPlaybackSpeed(1)
        PlayerManager.shared.tearDown()
        super.tearDown()
    }

    func testStandaloneLoadClearsEpisodeQueueAndExternalNavigation() {
        let manager = PlayerManager.shared
        let player = BackendLifecycleMockPlayer()
        install(player, on: manager)

        let episodes = [
            PlayerItem(title: "One", url: URL(string: "https://example.com/1.m3u8")!, episodeIndex: 1),
            PlayerItem(title: "Two", url: URL(string: "https://example.com/2.m3u8")!, episodeIndex: 2),
        ]
        manager.loadEpisodes(playerItems: episodes)
        manager.configureExternalEpisodeNavigation { _ in true }

        manager.load(
            playerItem: PlayerItem(
                title: "Movie",
                url: URL(string: "https://example.com/movie.m3u8")!
            )
        )

        XCTAssertTrue(manager.playerItems.isEmpty)
        XCTAssertEqual(manager.currentPlayerItemIndex, 0)
        XCTAssertEqual(manager.contentType, .movie)
        XCTAssertFalse(manager.canPlayNextItem)
        XCTAssertFalse(manager.canPlayPreviousItem)
    }

    func testEmptyEpisodeQueueClearsPreviouslyLoadedMedia() {
        let manager = PlayerManager.shared
        let player = BackendLifecycleMockPlayer()
        install(player, on: manager)
        manager.load(
            playerItem: PlayerItem(
                title: "Old movie",
                url: URL(string: "https://example.com/old.m3u8")!
            )
        )

        manager.loadEpisodes(playerItems: [])

        XCTAssertNil(manager.playerItem)
        XCTAssertNil(manager.currentPlayer)
        XCTAssertTrue(manager.playerItems.isEmpty)
        XCTAssertEqual(manager.currentPlayerItemIndex, 0)
        XCTAssertEqual(manager.contentType, .episode)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertGreaterThanOrEqual(player.stopCallCount, 1)
    }

    func testStopThenPlayReachesTheSameBackend() {
        let manager = PlayerManager.shared
        let player = BackendLifecycleMockPlayer()
        install(player, on: manager)

        manager.stop()
        manager.play()

        XCTAssertEqual(player.stopCallCount, 1)
        XCTAssertEqual(player.playCallCount, 1)
        XCTAssertTrue(manager.isPlaybackRequested)
    }

    func testInvalidSeekAndSpeedNeverReachBackend() {
        let manager = PlayerManager.shared
        let player = BackendLifecycleMockPlayer()
        install(player, on: manager)
        manager.duration = 120
        manager.setPlaybackSpeed(1.5)

        var seekResult: Bool?
        manager.seek(to: .nan) { seekResult = $0 }
        manager.setPlaybackSpeed(.infinity)
        manager.setPlaybackSpeed(-2)

        XCTAssertEqual(seekResult, false)
        XCTAssertTrue(player.seekTargets.isEmpty)
        XCTAssertEqual(manager.playbackSpeed, 1.5, accuracy: 0.001)
        XCTAssertEqual(player.playbackSpeed, 1.5, accuracy: 0.001)
    }

    func testStandardQuarterStepRatesReachAndSurviveBackendReplacement() {
        let manager = PlayerManager.shared
        let first = BackendLifecycleMockPlayer()
        install(first, on: manager)

        manager.setPlaybackSpeed(0.75)
        XCTAssertEqual(first.playbackSpeed, 0.75, accuracy: 0.001)
        manager.setPlaybackSpeed(1.75)
        XCTAssertEqual(first.playbackSpeed, 1.75, accuracy: 0.001)

        let replacement = BackendLifecycleMockPlayer()
        install(replacement, on: manager)
        XCTAssertEqual(manager.playbackSpeed, 1.75, accuracy: 0.001)
        XCTAssertEqual(replacement.playbackSpeed, 1.75, accuracy: 0.001)
    }

    func testInvalidVolumeNeverReachesBackend() {
        let manager = PlayerManager.shared
        let player = BackendLifecycleMockPlayer()
        install(player, on: manager)

        manager.volume = .nan
        manager.volume = .infinity

        XCTAssertEqual(player.volumeSetCallCount, 0)
        XCTAssertEqual(player.outputVolume, 0.5)
    }

    func testTerminalFailureClearsPlaybackIntentAndTransportState() {
        let manager = PlayerManager.shared
        let player = BackendLifecycleMockPlayer()
        install(player, on: manager)
        manager.play()
        manager.isBuffering = true
        manager.isMediaReady = true

        manager.playerDidFail(with: .mediaLoadFailed("fixture"))

        XCTAssertFalse(manager.isPlaybackRequested)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertFalse(manager.isBuffering)
        XCTAssertFalse(manager.isMediaReady)
    }

    func testIntegrationSubscriptionsAreCancelledAndDoNotMultiply() {
        let manager = PlayerManager.shared
        manager.setPlayer(type: .avPlayer)
        manager.play()
        let initialCount = manager.activeIntegrationSubscriptionCount
        XCTAssertGreaterThan(initialCount, 0)

        manager.tearDown()
        XCTAssertEqual(manager.activeIntegrationSubscriptionCount, 0)

        manager.setPlayer(type: .avPlayer)
        manager.play()
        XCTAssertEqual(manager.activeIntegrationSubscriptionCount, initialCount)
    }

    func testExternalPlaybackPolicySurvivesBackendRecreation() {
        let manager = PlayerManager.shared
        manager.isExternalPlaybackEnabled = true

        manager.setPlayer(type: .avPlayer)
        XCTAssertTrue((manager.currentPlayer as? AVPlayerWrapper)?.allowsExternalPlayback == true)

        manager.resetPlayer()
        manager.setPlayer(type: .avPlayer)
        XCTAssertTrue((manager.currentPlayer as? AVPlayerWrapper)?.allowsExternalPlayback == true)
    }

    func testSavedTracksAreConsumedBeforeSynchronousBackendCallbacks() {
        let manager = PlayerManager.shared
        let audio = TrackInfo(id: "audio", name: "Audio", languageCode: "en")
        let subtitle = TrackInfo(id: "subtitle", name: "Subtitle", languageCode: "en")
        let original = BackendLifecycleMockPlayer()
        original.availableAudioTracks = [audio]
        original.availableSubtitles = [subtitle]
        original.currentAudioTrack = audio
        original.currentSubtitleTrack = subtitle
        install(original, on: manager)
        manager.playerDidUpdateTracks()

        let replacement = BackendLifecycleMockPlayer()
        replacement.availableAudioTracks = [audio]
        replacement.availableSubtitles = [subtitle]
        replacement.reportsTrackChangesSynchronously = true
        manager.installPlayerBackend(replacement)
        manager.playerDidUpdateTracks()

        XCTAssertEqual(replacement.audioSelectionCallCount, 1)
        XCTAssertEqual(replacement.subtitleSelectionCallCount, 1)
    }

    func testAVSeekWithoutMediaCompletesWithFailure() {
        let wrapper = AVPlayerWrapper()
        var result: Bool?

        wrapper.seek(to: 10) { result = $0 }

        XCTAssertEqual(result, false)
    }

    func testAVStopRetainsLoadedItemForReplay() {
        let wrapper = AVPlayerWrapper()
        wrapper.load(url: URL(fileURLWithPath: "/dev/null"), lastPosition: nil)
        XCTAssertTrue(wrapper.hasLoadedMedia)

        wrapper.stop()

        XCTAssertTrue(wrapper.hasLoadedMedia)
    }

    func testSwitchingToTheStoredBuiltInTypeReplacesACustomBackend() {
        let manager = PlayerManager.shared
        manager.setPlayer(type: .avPlayer)
        manager.installPlayerBackend(BackendLifecycleMockPlayer())
        XCTAssertNil(manager.activeBuiltInPlayerType)

        manager.switchPlayer(to: .avPlayer)

        XCTAssertTrue(manager.currentPlayer is AVPlayerWrapper)
        XCTAssertEqual(manager.activeBuiltInPlayerType, .avPlayer)
    }

    func testEnsuringTheStoredBuiltInTypeReplacesACustomBackend() {
        let manager = PlayerManager.shared
        manager.setPlayer(type: .avPlayer)
        manager.installPlayerBackend(BackendLifecycleMockPlayer())

        manager.ensurePlayerConfigured(type: .avPlayer)

        XCTAssertTrue(manager.currentPlayer is AVPlayerWrapper)
        XCTAssertEqual(manager.activeBuiltInPlayerType, .avPlayer)
    }

    @MainActor
    func testTearDownCancelsExternalEpisodeNavigationTask() async {
        let manager = PlayerManager.shared
        manager.contentType = .episode
        let started = expectation(description: "navigation started")
        let escapedCancellation = expectation(description: "cancelled navigation must not finish")
        escapedCancellation.isInverted = true

        manager.configureExternalEpisodeNavigation(canPlayNext: true) { _ in
            started.fulfill()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                escapedCancellation.fulfill()
            }
            return true
        }
        manager.playNext()
        await fulfillment(of: [started], timeout: 1)

        manager.tearDown()
        await fulfillment(of: [escapedCancellation], timeout: 0.4)
        XCTAssertFalse(manager.isExternalEpisodeNavigationInProgress)
    }

    func testExternalNavigationConfiguredBeforeFirstEpisodeSurvivesReplacement() async {
        let manager = PlayerManager.shared
        let player = BackendLifecycleMockPlayer()
        install(player, on: manager)
        var navigationCount = 0
        let navigated = expectation(description: "external navigation invoked twice")
        navigated.expectedFulfillmentCount = 2

        manager.configureExternalEpisodeNavigation(canPlayNext: true) { _ in
            navigationCount += 1
            manager.load(
                playerItem: PlayerItem(
                    title: "Episode \(navigationCount)",
                    url: URL(string: "https://example.com/\(navigationCount).m3u8")!,
                    episodeIndex: navigationCount
                )
            )
            navigated.fulfill()
            return true
        }
        manager.load(
            playerItem: PlayerItem(
                title: "Episode zero",
                url: URL(string: "https://example.com/0.m3u8")!,
                episodeIndex: 0
            )
        )

        manager.playNext()
        while navigationCount < 1 { await Task.yield() }
        manager.playNext()
        await fulfillment(of: [navigated], timeout: 1)

        XCTAssertEqual(navigationCount, 2)
        XCTAssertTrue(manager.canPlayNextItem)
    }

    private func install(_ player: BackendLifecycleMockPlayer, on manager: PlayerManager) {
        manager.installPlayerBackend(player)
    }
}

@MainActor
private final class BackendLifecycleMockPlayer: PlayerProtocol, PlayerEventSource, PlayerVolumeControlling {
    var isPlaying = false
    var playbackSpeed: Float = 1
    var currentTime: Double = 0
    var duration: Double = 120
    var bufferedDuration: Double = 0
    var isBuffering = false
    var availableAudioTracks: [TrackInfo] = []
    var availableSubtitles: [TrackInfo] = []
    var currentAudioTrack: TrackInfo?
    var currentSubtitleTrack: TrackInfo?
    var playCallCount = 0
    var stopCallCount = 0
    var seekTargets: [Double] = []
    var lifecycleReporter: PlayerLifecycleReporting?
    var reportsTrackChangesSynchronously = false
    var audioSelectionCallCount = 0
    var subtitleSelectionCallCount = 0
    var outputVolume: Float = 0.5
    var volumeSetCallCount = 0

    func play() {
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
    }

    func seek(to time: Double, completion: (@MainActor (Bool) -> Void)?) {
        seekTargets.append(time)
        currentTime = time
        completion?(true)
    }

    func scrubForward(by seconds: TimeInterval) { currentTime += seconds }
    func scrubBackward(by seconds: TimeInterval) { currentTime -= seconds }
    func setOutputVolume(_ value: Float) {
        volumeSetCallCount += 1
        outputVolume = value
    }
    func selectAudioTrack(withID id: String) {
        audioSelectionCallCount += 1
        currentAudioTrack = availableAudioTracks.first(where: { $0.id == id })
        if reportsTrackChangesSynchronously {
            lifecycleReporter?.playerDidUpdateTracks()
        }
    }

    func selectSubtitle(withID id: String?) {
        subtitleSelectionCallCount += 1
        currentSubtitleTrack = id.flatMap { id in
            availableSubtitles.first(where: { $0.id == id })
        }
        if reportsTrackChangesSynchronously {
            lifecycleReporter?.playerDidUpdateTracks()
        }
    }

    func load(url: URL, lastPosition: Double?) {
        currentTime = lastPosition ?? 0
    }

    func getPlayerView() -> PKView { AVPlayerView() }
    func setupPiP() {}
    func startPiP() {}
    func stopPiP() {}
    func handlePinchGesture(scale: CGFloat) {}
    func setGravityToDefault() {}
    func setGravityToFill() {}
    func fetchStreamingInfo() -> StreamingInfo { .placeholder }
}
