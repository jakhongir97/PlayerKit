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
    
    func testLoadSingleItemSetsMovieContentTypeByDefault() {
        let movie = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)
        
        PlayerManager.shared.load(playerItem: movie)
        
        XCTAssertEqual(PlayerManager.shared.contentType, .movie)
        XCTAssertEqual(PlayerManager.shared.playerItem?.title, "Movie")
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
        
        AudioSessionManager.shared.onPauseRequested?()
        XCTAssertFalse(manager.isPlaying)
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

    @MainActor
    func testConfigureDubberTogglesFeatureState() {
        let manager = PlayerManager.shared

        manager.configureDubber(nil)
        XCTAssertFalse(manager.isDubberEnabled)

        manager.configureDubber(DubberConfiguration())
        XCTAssertTrue(manager.isDubberEnabled)
    }

    @MainActor
    func testConfigureDubberLoadsLanguageOptions() {
        let manager = PlayerManager.shared
        let configuration = DubberConfiguration(
            defaultLanguage: "en",
            defaultTranslateFrom: "ru",
            supportedLanguages: [
                DubberLanguageOption(code: "en", name: "English"),
                DubberLanguageOption(code: "uz", name: "Uzbek"),
            ],
            supportedSourceLanguages: [
                DubberLanguageOption(code: "auto", name: "Auto Detect"),
                DubberLanguageOption(code: "ru", name: "Russian"),
            ]
        )

        manager.configureDubber(configuration)

        XCTAssertEqual(manager.availableDubLanguages.map(\.code), ["en", "uz"])
        XCTAssertEqual(manager.availableDubSourceLanguages.map(\.code), ["auto", "ru"])
        XCTAssertEqual(manager.selectedDubLanguageCode, "en")
        XCTAssertEqual(manager.selectedDubSourceLanguageCode, "ru")
    }

    @MainActor
    func testSetDubLanguageUpdatesOnlySupportedCodes() {
        let manager = PlayerManager.shared
        let configuration = DubberConfiguration(
            supportedLanguages: [
                DubberLanguageOption(code: "uz", name: "Uzbek"),
                DubberLanguageOption(code: "en", name: "English"),
            ],
            supportedSourceLanguages: [
                DubberLanguageOption(code: "auto", name: "Auto Detect"),
                DubberLanguageOption(code: "ru", name: "Russian"),
            ]
        )

        manager.configureDubber(configuration)
        manager.setDubLanguage(code: "en")
        manager.setDubSourceLanguage(code: "ru")
        manager.setDubLanguage(code: "de")
        manager.setDubSourceLanguage(code: "fr")

        XCTAssertEqual(manager.selectedDubLanguageCode, "en")
        XCTAssertEqual(manager.selectedDubSourceLanguageCode, "ru")
    }

    @MainActor
    func testStartDubbedPlaybackWithoutConfigurationReportsError() async {
        let manager = PlayerManager.shared
        let movie = PlayerItem(title: "Movie", url: URL(string: "https://example.com/movie.m3u8")!)

        manager.load(playerItem: movie)
        manager.configureDubber(nil)

        await manager.startDubbedPlayback()

        XCTAssertEqual(manager.lastError, .dubberNotConfigured)
        XCTAssertFalse(manager.isDubLoading)
    }

    @MainActor
    func testStartDubbedPlaybackWithoutSourceReportsError() async {
        let manager = PlayerManager.shared

        manager.playerItem = nil
        manager.configureDubber(DubberConfiguration())

        await manager.startDubbedPlayback()

        XCTAssertEqual(manager.lastError, .dubberSourceMissing)
        XCTAssertFalse(manager.isDubLoading)
    }

    func testDubberUpdatePayloadDecodesSnakeCaseFields() throws {
        let data = Data(
            """
            {
              "status": "processing",
              "progress": "Generating audio",
              "segments_ready": 3,
              "total_segments": 12,
              "error": null
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(DubberClient.UpdatePayload.self, from: data)

        XCTAssertEqual(payload.status, "processing")
        XCTAssertEqual(payload.progress, "Generating audio")
        XCTAssertEqual(payload.segments_ready, 3)
        XCTAssertEqual(payload.total_segments, 12)
        XCTAssertNil(payload.error)
        XCTAssertTrue(payload.hasKnownFields)
    }

    func testDubberUpdatePayloadDecodesCamelCaseFields() throws {
        let data = Data(
            """
            {
              "status": "processing",
              "progress": "Generating audio",
              "segmentsReady": 5,
              "totalSegments": 18
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(DubberClient.UpdatePayload.self, from: data)

        XCTAssertEqual(payload.status, "processing")
        XCTAssertEqual(payload.progress, "Generating audio")
        XCTAssertEqual(payload.segments_ready, 5)
        XCTAssertEqual(payload.total_segments, 18)
        XCTAssertTrue(payload.hasKnownFields)
    }

    func testDubberDonePayloadDecodesStateFallback() throws {
        let data = Data(
            """
            {
              "state": "complete"
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(DubberClient.DonePayload.self, from: data)

        XCTAssertEqual(payload.status, "complete")
        XCTAssertTrue(payload.hasKnownFields)
    }

    func testAVPlayerWrapperStopDetachesPlayerFromRenderedView() {
        let wrapper = AVPlayerWrapper()
        let view = wrapper.getPlayerView()

        wrapper.load(url: URL(string: "https://example.com/movie.m3u8")!)

        XCTAssertNotNil(boundPlayer(from: view))

        wrapper.stop()

        XCTAssertNil(boundPlayer(from: view))
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
