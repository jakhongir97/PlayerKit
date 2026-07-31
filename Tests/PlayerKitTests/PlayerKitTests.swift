import XCTest
@testable import PlayerKit
#if os(macOS)
import AVKit
#endif

final class PlayerKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlayerManager.shared.resetPlayer()
        PlayerManager.shared.clearError()
        PlayerManager.shared.setPlayer()
    }
    
    override func tearDown() {
        PlayerManager.shared.resetPlayer()
        PlayerManager.shared.clearError()
        super.tearDown()
    }
    
    func testLoadEpisodesSetsEpisodeContentTypeAndCurrentItem() {
        let episode1 = PlayerItem(title: "Episode 1", url: URL(string: "https://example.com/e1.m3u8")!, episodeIndex: 1)
        let episode2 = PlayerItem(title: "Episode 2", url: URL(string: "https://example.com/e2.m3u8")!, episodeIndex: 2)
        
        PlayerManager.shared.loadEpisodes(playerItems: [episode1, episode2], currentIndex: 1)
        
        XCTAssertEqual(PlayerManager.shared.contentType, .episode)
        XCTAssertEqual(PlayerManager.shared.currentPlayerItemIndex, 1)
        XCTAssertEqual(PlayerManager.shared.playerItem?.title, "Episode 2")
    }

    func testSwitchPlayerPreservesCurrentMovieItemAcrossBackendSwitch() throws {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.currentTime = 123.45
        manager.currentPlayer = player

        let item = PlayerItem(
            title: "Movie",
            description: "Description",
            url: URL(string: "https://example.com/movie.m3u8")!,
            posterUrl: URL(string: "https://example.com/poster.jpg"),
            castVideoUrl: URL(string: "https://example.com/cast.mp4"),
            externalPlaybackContentType: "application/x-mpegURL",
            externalPlaybackDuration: 5400
        )
        manager.playerItem = item
        manager.contentType = .movie

        guard let targetType = alternatePlayerType(for: manager.selectedPlayerType) else {
            throw XCTSkip("Current platform exposes only one supported backend.")
        }

        manager.switchPlayer(to: targetType)

        XCTAssertEqual(manager.playerItem?.title, item.title)
        XCTAssertEqual(manager.playerItem?.description, item.description)
        XCTAssertEqual(manager.playerItem?.url, item.url)
        XCTAssertEqual(manager.playerItem?.posterUrl, item.posterUrl)
        XCTAssertEqual(manager.playerItem?.castVideoUrl, item.castVideoUrl)
        XCTAssertEqual(manager.playerItem?.externalPlaybackContentType, item.externalPlaybackContentType)
        XCTAssertEqual(manager.playerItem?.externalPlaybackDuration, item.externalPlaybackDuration)
        XCTAssertEqual(manager.playerItem?.lastPosition ?? -1, 123.45, accuracy: 0.001)
        XCTAssertEqual(manager.contentType, .movie)
    }

    func testSwitchPlayerPreservesPausedPlaybackIntent() throws {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.currentTime = 42
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.playerItem = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)

        manager.play()
        manager.pause()
        XCTAssertFalse(manager.isPlaybackRequested)

        guard let targetType = alternatePlayerType(for: manager.selectedPlayerType) else {
            throw XCTSkip("Current platform exposes only one supported backend.")
        }

        manager.switchPlayer(to: targetType)

        XCTAssertFalse(manager.isPlaybackRequested)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.playerItem?.lastPosition ?? -1, 42, accuracy: 0.001)
    }

    func testSwitchPlayerPreservesEpisodeQueueAndExternalNavigation() throws {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.currentTime = 88
        manager.currentPlayer = player

        let episode1 = PlayerItem(title: "Episode 1", url: URL(string: "https://example.com/e1.m3u8")!, episodeIndex: 1)
        let episode2 = PlayerItem(title: "Episode 2", url: URL(string: "https://example.com/e2.m3u8")!, episodeIndex: 2)
        manager.playerItems = [episode1, episode2]
        manager.currentPlayerItemIndex = 1
        manager.playerItem = episode2
        manager.contentType = .episode
        manager.configureExternalEpisodeNavigation(canPlayPrevious: true, canPlayNext: false) { _ in
            true
        }

        guard let targetType = alternatePlayerType(for: manager.selectedPlayerType) else {
            throw XCTSkip("Current platform exposes only one supported backend.")
        }

        manager.switchPlayer(to: targetType)

        XCTAssertEqual(manager.currentPlayerItemIndex, 1)
        XCTAssertEqual(manager.playerItems.count, 2)
        XCTAssertEqual(manager.playerItem?.title, "Episode 2")
        XCTAssertEqual(manager.playerItem?.lastPosition ?? -1, 88, accuracy: 0.001)
        XCTAssertEqual(manager.playerItems[1].lastPosition ?? -1, 88, accuracy: 0.001)
        XCTAssertTrue(manager.canPlayPreviousItem)
        XCTAssertFalse(manager.canPlayNextItem)

        manager.updateExternalEpisodeNavigationAvailability(canPlayPrevious: false, canPlayNext: true)

        XCTAssertFalse(manager.canPlayPreviousItem)
        XCTAssertTrue(manager.canPlayNextItem)
    }

    func testEnsurePlayerConfiguredUsesSwitchForLoadedContent() throws {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.currentTime = 64
        manager.currentPlayer = player

        let item = PlayerItem(
            title: "Movie",
            description: "Description",
            url: URL(string: "https://example.com/movie.m3u8")!,
            posterUrl: URL(string: "https://example.com/poster.jpg")
        )
        manager.playerItem = item
        manager.contentType = .movie

        guard let targetType = alternatePlayerType(for: manager.selectedPlayerType) else {
            throw XCTSkip("Current platform exposes only one supported backend.")
        }
        manager.ensurePlayerConfigured(type: targetType)

        XCTAssertEqual(manager.selectedPlayerType, targetType)
        XCTAssertEqual(manager.playerItem?.title, item.title)
        XCTAssertEqual(manager.playerItem?.url, item.url)
        XCTAssertEqual(manager.playerItem?.lastPosition ?? -1, 64, accuracy: 0.001)
        XCTAssertEqual(manager.contentType, .movie)
    }

    func testPlayNextUsesExternalEpisodeNavigationHandlerInsteadOfLocalEpisodeList() async {
        let manager = PlayerManager.shared
        let episode1 = PlayerItem(title: "Episode 1", url: URL(string: "https://example.com/e1.m3u8")!, episodeIndex: 1)
        let episode2 = PlayerItem(title: "Episode 2", url: URL(string: "https://example.com/e2.m3u8")!, episodeIndex: 2)
        let navigationExpectation = expectation(description: "External episode navigation invoked")
        let recorder = EpisodeNavigationRecorder()

        await MainActor.run {
            manager.playerItems = [episode1, episode2]
            manager.currentPlayerItemIndex = 0
            manager.contentType = .episode
            manager.configureExternalEpisodeNavigation(canPlayPrevious: false, canPlayNext: true) { direction in
                await recorder.record(direction)
                navigationExpectation.fulfill()
                return true
            }

            manager.playNext()
        }

        await fulfillment(of: [navigationExpectation], timeout: 1.0)
        let receivedDirections = await recorder.snapshot()

        XCTAssertEqual(receivedDirections.count, 1)
        XCTAssertEqual(receivedDirections.first, .next)
        XCTAssertEqual(manager.currentPlayerItemIndex, 0)
        XCTAssertFalse(manager.isExternalEpisodeNavigationInProgress)
    }

    func testExternalEpisodeNavigationAvailabilityOverridesPrevNextAvailability() {
        let manager = PlayerManager.shared
        manager.contentType = .episode

        manager.configureExternalEpisodeNavigation(canPlayPrevious: false, canPlayNext: true) { _ in
            true
        }

        XCTAssertFalse(manager.canPlayPreviousItem)
        XCTAssertTrue(manager.canPlayNextItem)

        manager.updateExternalEpisodeNavigationAvailability(canPlayPrevious: true, canPlayNext: false)

        XCTAssertTrue(manager.canPlayPreviousItem)
        XCTAssertFalse(manager.canPlayNextItem)
    }
    
    func testLoadSingleItemSetsMovieContentTypeByDefault() {
        let movie = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)
        
        PlayerManager.shared.load(playerItem: movie)
        
        XCTAssertEqual(PlayerManager.shared.contentType, .movie)
        XCTAssertEqual(PlayerManager.shared.playerItem?.title, "Movie")
    }

    func testSupportedPlayerTypesMatchCurrentPlatform() {
        if PlayerType.vlcPlayer.isSupported {
        XCTAssertEqual(PlayerType.supportedCases, [.vlcPlayer, .avPlayer])
        XCTAssertTrue(PlayerType.vlcPlayer.isSupported)
        } else {
        XCTAssertEqual(PlayerType.supportedCases, [.avPlayer])
        XCTAssertFalse(PlayerType.vlcPlayer.isSupported)
        }
    }

    func testDesktopVLCWrapperCanStartRuntimeUpdatesWithoutLoadedMedia() throws {
        #if os(macOS) && !canImport(VLCKit)
        let wrapper = DesktopVLCPlayerWrapper()

        wrapper.startRuntimeStateUpdates()

        XCTAssertFalse(wrapper.isPlaying)
        XCTAssertEqual(wrapper.currentTime, 0, accuracy: 0.001)
        XCTAssertEqual(wrapper.duration, 0, accuracy: 0.001)

        wrapper.stopRuntimeStateUpdates()
        #else
        throw XCTSkip("Desktop libVLC wrapper is not the active backend on this platform.")
        #endif
    }

    func testUserDefaultsResolvesUnsupportedStoredPlayerType() {
        let suiteName = "PlayerKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(PlayerType.vlcPlayer.rawValue, forKey: "PlayerKit.SelectedPlayerType")

        XCTAssertEqual(
            defaults.loadPlayerType(),
            PlayerType.vlcPlayer.isSupported ? .vlcPlayer : .avPlayer
        )
    }
    
    func testReportErrorUpdatesStateAndPostsNotification() {
        let expectation = expectation(forNotification: .PlayerKitDidFail, object: nil) { notification in
            guard let error = notification.object as? PlayerKitError else { return false }
            return error == .castSessionUnavailable
        }
        
        PlayerManager.shared.reportError(.castSessionUnavailable)
        
        XCTAssertEqual(PlayerManager.shared.lastError, .castSessionUnavailable)
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testTrackInfoPublicInitializerAndProperties() {
        let track = TrackInfo(id: "eng-main", name: "English", languageCode: "en")
        
        XCTAssertEqual(track.id, "eng-main")
        XCTAssertEqual(track.name, "English")
        XCTAssertEqual(track.languageCode, "en")
    }
    
    func testStreamingInfoPlaceholderDefaults() {
        XCTAssertEqual(StreamingInfo.placeholder.frameRate, "Unknown")
        XCTAssertEqual(StreamingInfo.placeholder.videoBitrate, "0 Mbps")
        XCTAssertEqual(StreamingInfo.placeholder.resolution, "Unknown")
        XCTAssertEqual(StreamingInfo.placeholder.bufferDuration, "0 sec")
    }
    
    func testSafeSubscriptReturnsNilForOutOfBounds() {
        let values = [10, 20, 30]
        
        XCTAssertEqual(values[safe: 1], 20)
        XCTAssertNil(values[safe: 10])
    }
    
    func testLifecycleCallbacksUpdatePlayerManagerState() {
        let manager = PlayerManager.shared
        
        manager.playerDidChangePiPState(isActive: true)
        manager.playerDidBecomeReady()
        manager.playerDidFail(with: .castURLMissing)
        
        XCTAssertTrue(manager.isPiPActive)
        XCTAssertTrue(manager.isMediaReady)
        XCTAssertEqual(manager.lastError, .castURLMissing)
    }

    func testLoadMarksPlaybackAsStartingImmediately() {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.autoplayOnLoad = false
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)

        let item = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)
        manager.load(playerItem: item)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.isBuffering)
        XCTAssertTrue(manager.isPlaybackRequested)
        XCTAssertEqual(manager.currentTime, 0, accuracy: 0.001)
    }

    func testPlayerDidBecomeReadyAutoPlaysFreshLoad() async {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.autoplayOnLoad = false
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)

        let item = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)
        manager.load(playerItem: item)
        manager.playerDidBecomeReady()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(manager.isMediaReady)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.isPlaybackRequested)
        XCTAssertGreaterThanOrEqual(player.playCallCount, 1)
    }

    func testPlayerDidBecomeReadyRetriesAutoplayWhenFirstPlayIsIgnored() async {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.autoplayOnLoad = false
        player.playAttemptsBeforePlaying = 2
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)

        let item = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)
        manager.load(playerItem: item)
        manager.playerDidBecomeReady()

        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.isPlaybackRequested)
        XCTAssertGreaterThanOrEqual(player.playCallCount, 2)
    }

    func testPlayerDidBecomeReadyKeepsRetryingWhenStartupFalselyReportsPlaying() async {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.autoplayOnLoad = false
        player.playAttemptsBeforePlaying = 4
        player.reportsPlayingDuringStartup = true
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)

        let item = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)
        manager.load(playerItem: item)
        manager.playerDidBecomeReady()

        try? await Task.sleep(nanoseconds: 1_400_000_000)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.isPlaybackRequested)
        XCTAssertGreaterThanOrEqual(player.playCallCount, 4)
    }
    
    func testCastManagerReceivesPlayerItemProviderBinding() {
        let manager = PlayerManager.shared
        let movie = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)
        
        manager.playerItem = movie
        
        XCTAssertEqual(manager.castManager.currentPlayerItemProvider?()?.title, "Movie")
    }
    
    func testCastManagerErrorCallbackReportsErrorToPlayerManager() {
        let manager = PlayerManager.shared
        
        manager.castManager.onError?(.castSessionUnavailable)
        
        XCTAssertEqual(manager.lastError, .castSessionUnavailable)
    }
    
    func testAudioSessionCallbacksControlPlaybackState() {
        let manager = PlayerManager.shared
        
        AudioSessionManager.shared.onResumeRequested?()
        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.isPlaybackRequested)
        
        AudioSessionManager.shared.onPauseRequested?()
        XCTAssertFalse(manager.isPlaying)
        XCTAssertFalse(manager.isPlaybackRequested)
    }

    func testPlayerDidStallDoesNotResumeWhenPlaybackWasPaused() {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)

        manager.play()
        manager.pause()
        manager.playerDidStall()

        XCTAssertEqual(player.playCallCount, 1)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertTrue(manager.isBuffering)
        XCTAssertFalse(manager.isPlaybackRequested)
    }

    func testPlayerDidStallResumesWhenPlaybackShouldContinue() async {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.isMediaReady = true

        manager.play()
        player.isPlaying = false
        manager.playerDidStall()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(player.playCallCount, 2)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.isPlaybackRequested)
    }

    func testPlaybackRequestRemainsPlayingDuringTransientStall() {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.isMediaReady = true

        manager.play()
        player.isPlaying = false
        manager.playerDidStall()

        XCTAssertTrue(manager.isPlaybackRequested)
        XCTAssertTrue(manager.isBuffering)
    }

    func testPlayerFacadeLoadURLCreatesDefaultPlayerItem() {
        let manager = PlayerManager.shared
        let player = Player(playerManager: manager)
        let url = URL(string: "https://example.com/movie.m3u8")!

        player.load(url: url)

        XCTAssertEqual(manager.playerItem?.url, url)
        XCTAssertEqual(manager.playerItem?.title, "movie.m3u8")
        XCTAssertEqual(manager.contentType, .movie)
    }

    func testPlayerItemBridgesCastAndExternalPlaybackURLs() {
        let castURL = URL(string: "https://example.com/cast.mp4")!
        let item = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!, castVideoUrl: castURL)

        XCTAssertEqual(item.castVideoUrl, castURL)
        XCTAssertEqual(item.externalPlaybackURL, castURL)
        XCTAssertEqual(item.preferredExternalPlaybackURL, castURL)
    }

    func testPlayerItemInfersHLSExternalPlaybackContentType() {
        let item = PlayerItem(
            title: "Movie",
            url: URL(string: "https://example.com/stream.m3u8")!
        )

        XCTAssertEqual(item.preferredExternalPlaybackContentType, "application/x-mpegURL")
    }

    func testPlayerItemPrefersExplicitExternalPlaybackContentType() {
        let item = PlayerItem(
            title: "Movie",
            url: URL(string: "https://example.com/stream.m3u8")!,
            externalPlaybackContentType: "video/custom"
        )

        XCTAssertEqual(item.preferredExternalPlaybackContentType, "video/custom")
    }

    func testPlayerFacadeLoadPreservesExternalPlaybackMetadata() {
        let manager = PlayerManager.shared
        let player = Player(playerManager: manager)
        let playbackURL = URL(string: "https://example.com/movie.m3u8")!
        let externalURL = URL(string: "https://example.com/movie.mp4")!

        player.load(
            url: playbackURL,
            title: "Movie",
            externalPlaybackURL: externalURL,
            externalPlaybackContentType: "video/mp4",
            externalPlaybackDuration: 5400
        )

        XCTAssertEqual(manager.playerItem?.url, playbackURL)
        XCTAssertEqual(manager.playerItem?.externalPlaybackURL, externalURL)
        XCTAssertEqual(manager.playerItem?.castVideoUrl, externalURL)
        XCTAssertEqual(manager.playerItem?.externalPlaybackContentType, "video/mp4")
        XCTAssertEqual(manager.playerItem?.externalPlaybackDuration, 5400)
    }

    func testPlayerFacadeLoadEpisodesSetsEpisodeContext() {
        let manager = PlayerManager.shared
        let player = Player(playerManager: manager)
        let episode1 = PlayerItem(title: "Episode 1", url: URL(string: "https://example.com/e1.m3u8")!, episodeIndex: 1)
        let episode2 = PlayerItem(title: "Episode 2", url: URL(string: "https://example.com/e2.m3u8")!, episodeIndex: 2)

        player.load(playerItems: [episode1, episode2], currentIndex: 1)

        XCTAssertEqual(manager.contentType, .episode)
        XCTAssertEqual(manager.currentPlayerItemIndex, 1)
        XCTAssertEqual(manager.playerItem?.title, "Episode 2")
    }

    func testPlayerFacadePlayPauseUpdatesPlaybackState() {
        let manager = PlayerManager.shared
        let player = Player(playerManager: manager)

        player.play()
        XCTAssertTrue(manager.isPlaying)

        player.pause()
        XCTAssertFalse(manager.isPlaying)
    }

    func testPlayerManagerSeekUpdatesTimeAndInvokesCompletion() {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.duration = 600

        let expectation = expectation(description: "seek completion")
        manager.seek(to: 142) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(player.currentTime, 142, accuracy: 0.001)
        XCTAssertEqual(manager.currentTime, 142, accuracy: 0.001)
    }

    func testPlayerManagerSeekResumesPlaybackWhenSeekInterruptsPlayback() async {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.pauseOnSeek = true
        player.ignoredPlayAttemptsAfterSeek = 1
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.duration = 600
        manager.isMediaReady = true

        manager.play()
        manager.seek(to: 142)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertGreaterThanOrEqual(player.playCallCount, 3)
        XCTAssertEqual(player.currentTime, 142, accuracy: 0.001)
    }

    func testPlayerManagerSeekDoesNotResumeWhenPlaybackWasPaused() async {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        player.pauseOnSeek = true
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.duration = 600
        manager.isMediaReady = true

        manager.pause()
        manager.seek(to: 84)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(player.playCallCount, 0)
        XCTAssertEqual(player.currentTime, 84, accuracy: 0.001)
    }

    func testSelectAudioTrackResumesPlaybackWhenSwitchPausesBackend() async {
        let manager = PlayerManager.shared
        let player = MockPlayer()
        let originalTrack = TrackInfo(id: "audio-en", name: "English", languageCode: "en")
        let replacementTrack = TrackInfo(id: "audio-ru", name: "Russian", languageCode: "ru")
        player.availableAudioTracks = [originalTrack, replacementTrack]
        player.currentAudioTrack = originalTrack
        player.pauseOnAudioTrackSelection = true
        manager.currentPlayer = player
        manager.playbackManager = PlaybackManager(player: player, playerManager: manager)
        manager.trackManager = TrackManager(player: player)
        manager.isMediaReady = true
        manager.refreshTrackInfo()

        manager.play()
        manager.selectAudioTrack(track: replacementTrack)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(player.currentAudioTrack?.id, replacementTrack.id)
        XCTAssertEqual(manager.selectedAudio?.id, replacementTrack.id)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.isPlaybackRequested)
        XCTAssertGreaterThanOrEqual(player.playCallCount, 2)
    }

    func testPlayerManagerSeekReportsFailureWithoutDuration() {
        let manager = PlayerManager.shared

        var result: Bool?
        manager.duration = 0
        manager.seek(to: 20) { success in
            result = success
        }

        XCTAssertEqual(result, false)
    }

    func testAVPlayerWrapperStopDetachesPlayerFromRenderedView() {
        let wrapper = AVPlayerWrapper()
        let view = wrapper.getPlayerView()

        wrapper.load(url: URL(string: "https://example.com/movie.m3u8")!)

        XCTAssertNotNil(boundPlayer(from: view))

        wrapper.stop()

        XCTAssertNil(boundPlayer(from: view))
    }

    func testAVPlayerWrapperPlaybackFailureReportsLifecycleError() {
        let wrapper = AVPlayerWrapper()
        let reporter = MockPlayerLifecycleReporter()
        let view = wrapper.getPlayerView()
        let expectation = expectation(description: "playback failure reported")

        reporter.onFail = { error in
            XCTAssertEqual(error, .mediaLoadFailed("resource unavailable"))
            expectation.fulfill()
        }

        wrapper.lifecycleReporter = reporter
        wrapper.load(url: URL(string: "https://example.com/movie.m3u8")!)

        guard let player = boundPlayer(from: view),
              let item = player.currentItem else {
            XCTFail("Expected AVPlayer current item to exist")
            return
        }

        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            userInfo: [
                AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(
                    domain: NSURLErrorDomain,
                    code: URLError.resourceUnavailable.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "resource unavailable"]
                )
            ]
        )

        wait(for: [expectation], timeout: 1.0)
    }

    func testAVPlayerWrapperKeepsAutomaticStallWaitingEnabled() {
        let wrapper = AVPlayerWrapper()
        let view = wrapper.getPlayerView()

        wrapper.load(url: URL(string: "https://example.com/movie.m3u8")!)

        guard let player = boundPlayer(from: view) else {
            XCTFail("Expected bound AVPlayer")
            return
        }

        XCTAssertTrue(player.automaticallyWaitsToMinimizeStalling)
    }

    private func boundPlayer(from view: PKView, file: StaticString = #filePath, line: UInt = #line) -> AVPlayer? {
        #if os(macOS)
        if let playerView = view as? AVKit.AVPlayerView {
            return playerView.player
        }
        #endif

        if let playerView = view as? PlayerKit.AVPlayerView {
            return playerView.player
        }

        XCTFail("Unexpected player view type: \(String(reflecting: type(of: view)))", file: file, line: line)
        return nil
    }
}

private final class MockPlayerLifecycleReporter: PlayerLifecycleReporting {
    var onFail: ((PlayerKitError) -> Void)?

    func playerDidBecomeReady() {}
    func playerDidUpdateTracks() {}
    func playerDidEndPlayback() {}
    func playerDidChangePiPState(isActive: Bool) {}
    func playerDidStall() {}

    func playerDidFail(with error: PlayerKitError) {
        onFail?(error)
    }
}

private final class MockPlayer: PlayerProtocol {
    var isPlaying = false
    var playbackSpeed: Float = 1
    var currentTime: Double = 0
    var duration: Double = 600
    var bufferedDuration: Double = 0
    var isBuffering = false
    var availableAudioTracks: [TrackInfo] = []
    var availableSubtitles: [TrackInfo] = []
    var currentAudioTrack: TrackInfo?
    var currentSubtitleTrack: TrackInfo?
    var playCallCount = 0
    var pauseCallCount = 0
    var autoplayOnLoad = true
    var playAttemptsBeforePlaying = 1
    var reportsPlayingDuringStartup = false
    var pauseOnSeek = false
    var pauseOnAudioTrackSelection = false
    var ignoredPlayAttemptsAfterSeek = 0
    private var ignoredPlayAttemptsRemaining = 0

    func play() {
        playCallCount += 1
        if ignoredPlayAttemptsRemaining > 0 {
            ignoredPlayAttemptsRemaining -= 1
            isPlaying = false
            return
        }
        if playCallCount >= playAttemptsBeforePlaying {
            isPlaying = true
        } else {
            isPlaying = reportsPlayingDuringStartup
        }
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func stop() {
        isPlaying = false
    }

    func seek(to time: Double, completion: ((Bool) -> Void)?) {
        currentTime = time
        if pauseOnSeek {
            isPlaying = false
            ignoredPlayAttemptsRemaining = max(ignoredPlayAttemptsRemaining, ignoredPlayAttemptsAfterSeek)
        }
        completion?(true)
    }

    func scrubForward(by seconds: TimeInterval) {
        currentTime += seconds
    }

    func scrubBackward(by seconds: TimeInterval) {
        currentTime -= seconds
    }

    func selectAudioTrack(withID id: String) {
        currentAudioTrack = availableAudioTracks.first(where: { $0.id == id })
        if pauseOnAudioTrackSelection {
            isPlaying = false
        }
    }

    func selectSubtitle(withID id: String?) {
        currentSubtitleTrack = availableSubtitles.first(where: { $0.id == id })
    }

    func load(url: URL, lastPosition: Double?) {
        currentTime = lastPosition ?? 0
        isPlaying = autoplayOnLoad
    }

    func getPlayerView() -> PKView {
        PlayerKit.AVPlayerView()
    }

    func setupPiP() {}
    func startPiP() {}
    func stopPiP() {}
    func handlePinchGesture(scale: CGFloat) {}
    func setGravityToDefault() {}
    func setGravityToFill() {}

    func fetchStreamingInfo() -> StreamingInfo {
        .placeholder
    }
}

private actor EpisodeNavigationRecorder {
    private var directions: [PlayerEpisodeNavigationDirection] = []

    func record(_ direction: PlayerEpisodeNavigationDirection) {
        directions.append(direction)
    }

    func snapshot() -> [PlayerEpisodeNavigationDirection] {
        directions
    }
}

private func alternatePlayerType(for type: PlayerType) -> PlayerType? {
    PlayerType.supportedCases.first(where: { $0 != type })
}
