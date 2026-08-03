import XCTest
@testable import PlayerKit

@MainActor
final class PlaybackRecoveryRegressionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlayerManager.shared.tearDown()
        PlayerManager.shared.autoplay = true
        PlayerManager.shared.onPlaybackRetryRequested = nil
    }

    override func tearDown() {
        PlayerManager.shared.onPlaybackRetryRequested = nil
        PlayerManager.shared.voiceControlRunningOverride = nil
        PlayerManager.shared.autoplay = true
        PlayerManager.shared.tearDown()
        super.tearDown()
    }

    func testBackendEndEventWinsOverLaggingTimeline() {
        let manager = PlayerManager.shared
        let backend = RecoveryMockPlayer()
        manager.installPlayerBackend(backend)
        manager.load(playerItem: item("movie"))
        manager.duration = 0
        manager.currentTime = 0

        manager.playerDidEndPlayback()

        XCTAssertTrue(manager.isVideoEnded)
        XCTAssertFalse(manager.isPlaybackRequested)
        XCTAssertFalse(manager.isBuffering)
    }

    func testFailedExternalAutoAdvanceFallsBackToEndCardState() async {
        let manager = PlayerManager.shared
        let backend = RecoveryMockPlayer()
        manager.installPlayerBackend(backend)
        manager.configureExternalEpisodeNavigation(canPlayNext: true) { _ in false }
        manager.load(
            playerItem: PlayerItem(
                title: "episode",
                url: URL(string: "https://example.com/episode.m3u8")!,
                episodeIndex: 1
            )
        )

        manager.playerDidEndPlayback()
        while manager.isExternalEpisodeNavigationInProgress { await Task.yield() }

        XCTAssertTrue(manager.isVideoEnded)
    }

    func testNewItemClearsPublishedTracksBeforeBackendReportsItsOwn() {
        let manager = PlayerManager.shared
        let backend = RecoveryMockPlayer()
        let audio = TrackInfo(id: "old-audio", name: "Old audio", languageCode: "en")
        let subtitle = TrackInfo(id: "old-subtitle", name: "Old subtitle", languageCode: "en")
        backend.availableAudioTracks = [audio]
        backend.availableSubtitles = [subtitle]
        backend.currentAudioTrack = audio
        backend.currentSubtitleTrack = subtitle
        manager.installPlayerBackend(backend)
        manager.load(playerItem: item("old"))
        manager.playerDidUpdateTracks()
        XCTAssertEqual(manager.availableAudioTracks, [audio])

        backend.availableAudioTracks = []
        backend.availableSubtitles = []
        backend.currentAudioTrack = nil
        backend.currentSubtitleTrack = nil
        manager.load(playerItem: item("new"))

        XCTAssertTrue(manager.availableAudioTracks.isEmpty)
        XCTAssertTrue(manager.availableSubtitles.isEmpty)
        XCTAssertNil(manager.selectedAudio)
        XCTAssertNil(manager.selectedSubtitle)
    }

    func testPausedBackendReplacementRestoresPausedIntentDuringLoad() {
        let manager = PlayerManager.shared
        let original = RecoveryMockPlayer()
        manager.installPlayerBackend(original)
        manager.load(playerItem: item("movie"))
        manager.pause()

        let replacement = RecoveryMockPlayer()
        replacement.eagerlyPlaysOnLoad = true
        manager.installPlayerBackend(replacement)

        XCTAssertFalse(manager.isPlaybackRequested)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertFalse(replacement.isPlaying)
        XCTAssertEqual(replacement.playCallCount, 0)
        XCTAssertEqual(replacement.pauseCallCount, 1)
    }

    func testRetryCanRefreshAnExpiredURLAndResumeAtCurrentPosition() async {
        let manager = PlayerManager.shared
        let backend = RecoveryMockPlayer()
        manager.installPlayerBackend(backend)
        manager.load(playerItem: item("expired"))
        backend.currentTime = 37
        manager.playerDidFail(with: .mediaLoadFailed("signed URL expired"))
        XCTAssertTrue(manager.isPlaybackErrorTerminal)
        let refreshed = item("refreshed")
        manager.onPlaybackRetryRequested = { _ in refreshed }

        manager.retryPlayback()
        while manager.isRetryingPlayback { await Task.yield() }

        XCTAssertEqual(manager.playerItem?.url, refreshed.url)
        XCTAssertEqual(backend.loadedURLs.last, refreshed.url)
        XCTAssertEqual(backend.loadedPositions.last.flatMap { $0 } ?? -1, 37, accuracy: 0.001)
        XCTAssertNil(manager.lastError)
        XCTAssertFalse(manager.isPlaybackErrorTerminal)
        XCTAssertTrue(manager.isPlaybackRequested)
    }

    func testCancelledURLRefreshCannotReplaceANewerItem() async {
        let manager = PlayerManager.shared
        let backend = RecoveryMockPlayer()
        manager.installPlayerBackend(backend)
        manager.load(playerItem: item("expired"))
        manager.playerDidFail(with: .mediaLoadFailed("expired"))
        let refreshStarted = expectation(description: "refresh started")
        manager.onPlaybackRetryRequested = { _ in
            refreshStarted.fulfill()
            try? await Task.sleep(nanoseconds: 300_000_000)
            return self.item("stale-refresh")
        }

        manager.retryPlayback()
        await fulfillment(of: [refreshStarted], timeout: 1)
        let newer = item("newer")
        manager.load(playerItem: newer)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.playerItem?.url, newer.url)
        XCTAssertEqual(backend.loadedURLs.last, newer.url)
    }

    func testErrorPresentationNeverEchoesBackendDetail() {
        let secret = "https://cdn.example/video.m3u8?token=super-secret"
        let presentation = PlaybackErrorPresentation(.mediaLoadFailed(secret))

        XCTAssertTrue(presentation.blocksPlayback)
        XCTAssertTrue(presentation.isRetryable)
        XCTAssertFalse(presentation.message.contains(secret))
        XCTAssertFalse(PlaybackErrorPresentation(.pictureInPictureFailed(secret)).blocksPlayback)
        XCTAssertTrue(
            PlaybackErrorPresentation(
                .unknown(secret),
                terminalPlaybackFailure: true
            ).blocksPlayback
        )
    }

    func testPublicErrorPresentationDoesNotEchoBackendDetail() {
        let secret = "https://cdn.example/video.m3u8?token=super-secret"

        for error in [
            PlayerKitError.mediaLoadFailed(secret),
            .pictureInPictureFailed(secret),
            .externalPlaybackFailed(secret),
            .unknown(secret)
        ] {
            XCTAssertFalse(error.userFacingDescription.contains(secret))
        }
    }

    func testVoiceControlOverrideImmediatelyRestoresHiddenControls() {
        let manager = PlayerManager.shared
        manager.voiceControlRunningOverride = false
        manager.controlVisibilityManager.hideControls()
        XCTAssertFalse(manager.areControlsVisible)

        manager.voiceControlRunningOverride = true

        XCTAssertTrue(manager.areControlsVisible)
    }

    func testRecoveryActionsStackAtAccessibilityTextSizes() {
        XCTAssertFalse(PlaybackRecoveryOverlayView.stacksActions(for: .large))
        XCTAssertTrue(PlaybackRecoveryOverlayView.stacksActions(for: .accessibilityMedium))
    }

    private func item(_ name: String) -> PlayerItem {
        PlayerItem(
            title: name,
            url: URL(string: "https://example.com/\(name).m3u8")!
        )
    }
}

@MainActor
private final class RecoveryMockPlayer: PlayerProtocol, PlayerEventSource {
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
    weak var lifecycleReporter: PlayerLifecycleReporting?
    private(set) var loadedURLs: [URL] = []
    private(set) var loadedPositions: [Double?] = []
    var eagerlyPlaysOnLoad = false
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    func play() {
        playCallCount += 1
        isPlaying = true
    }
    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }
    func stop() { isPlaying = false }
    func seek(to time: Double, completion: (@MainActor (Bool) -> Void)?) {
        currentTime = time
        completion?(true)
    }
    func scrubForward(by seconds: TimeInterval) { currentTime += seconds }
    func scrubBackward(by seconds: TimeInterval) { currentTime -= seconds }
    func load(url: URL, lastPosition: Double?) {
        loadedURLs.append(url)
        loadedPositions.append(lastPosition)
        currentTime = lastPosition ?? 0
        if eagerlyPlaysOnLoad {
            isPlaying = true
        }
    }
    func selectAudioTrack(withID id: String) {
        currentAudioTrack = availableAudioTracks.first { $0.id == id }
    }
    func selectSubtitle(withID id: String?) {
        currentSubtitleTrack = id.flatMap { selectedID in
            availableSubtitles.first { $0.id == selectedID }
        }
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
