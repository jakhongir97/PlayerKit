import XCTest
@testable import PlayerKit

final class PlayerQoEEventReducerTests: XCTestCase {
    func testLifecycleEventsAreOrderedAndDuplicateEdgesAreSuppressed() {
        var reducer = PlayerQoEEventReducer()
        var events: [PlayerQoEEvent] = []

        events += reducer.loadRequested(autoplay: true)
        events += reducer.playRequested()
        events += reducer.runtimeChanged(isPlaying: true, isBuffering: false)
        events += reducer.ready()
        events += reducer.ready()
        events += reducer.stallStarted()
        events += reducer.stallStarted()
        events += reducer.runtimeChanged(isPlaying: false, isBuffering: true)
        events += reducer.runtimeChanged(isPlaying: true, isBuffering: false)
        events += reducer.pauseRequested()
        events += reducer.seekCompleted(targetTime: 42, succeeded: true)
        events += reducer.completed()
        events += reducer.fatalError()
        events += reducer.exited()
        events += reducer.exited()

        XCTAssertEqual(events, [
            .loadRequested(autoplay: true),
            .playRequested,
            .ready,
            .playbackStarted,
            .stallStarted,
            .stallEnded,
            .pauseRequested,
            .seekCompleted(targetTime: 42, succeeded: true),
            .completed,
            .exited,
        ])
    }

    func testFatalEventClosesAStallAndANewLoadResetsTheSession() {
        var reducer = PlayerQoEEventReducer()

        XCTAssertTrue(reducer.playRequested().isEmpty)
        XCTAssertEqual(reducer.loadRequested(autoplay: false), [.loadRequested(autoplay: false)])
        XCTAssertEqual(reducer.ready(), [.ready])
        XCTAssertEqual(
            reducer.runtimeChanged(isPlaying: true, isBuffering: false),
            [.playbackStarted]
        )
        XCTAssertEqual(reducer.stallStarted(), [.stallStarted])
        XCTAssertEqual(reducer.fatalError(), [.stallEnded, .fatalError])
        XCTAssertTrue(reducer.seekCompleted(targetTime: 10, succeeded: false).isEmpty)
        XCTAssertEqual(reducer.exited(), [.exited])

        XCTAssertEqual(reducer.loadRequested(autoplay: true), [.loadRequested(autoplay: true)])
        XCTAssertTrue(reducer.seekCompleted(targetTime: .nan, succeeded: false).isEmpty)
        XCTAssertEqual(
            reducer.seekCompleted(targetTime: 0, succeeded: false),
            [.seekCompleted(targetTime: 0, succeeded: false)]
        )
    }
}

@MainActor
final class PlayerQoEEventIntegrationTests: XCTestCase {
    func testManagerPublishesLifecycleEventsFromExistingBackendSignals() {
        let manager = PlayerManager.shared
        manager.onQoEEvent = nil
        manager.tearDown()
        manager.autoplay = true
        let backend = QoEMockPlayer()
        manager.installPlayerBackend(backend)

        var events: [PlayerQoEEvent] = []
        manager.onQoEEvent = { events.append($0) }
        defer {
            manager.tearDown()
            manager.onQoEEvent = nil
        }

        manager.load(
            playerItem: PlayerItem(
                title: "Episode",
                url: URL(string: "https://example.com/episode.m3u8")!,
                episodeIndex: 1
            )
        )
        manager.play()
        backend.lifecycleReporter?.playerDidBecomeReady()
        backend.emitRuntime(isPlaying: true, isBuffering: false)
        backend.lifecycleReporter?.playerDidStall()
        backend.emitRuntime(isPlaying: false, isBuffering: true)
        backend.emitRuntime(isPlaying: true, isBuffering: false)
        manager.pause()
        manager.seek(to: 42)
        backend.lifecycleReporter?.playerDidEndPlayback()
        manager.tearDown()

        XCTAssertEqual(events, [
            .loadRequested(autoplay: true),
            .playRequested,
            .ready,
            .playbackStarted,
            .stallStarted,
            .stallEnded,
            .pauseRequested,
            .seekCompleted(targetTime: 42, succeeded: true),
            .completed,
            .exited,
        ])
    }

    func testFatalEventPrecedesASynchronousFailureObserverExit() {
        let manager = PlayerManager.shared
        manager.onQoEEvent = nil
        manager.tearDown()
        let backend = QoEMockPlayer()
        manager.installPlayerBackend(backend)

        var events: [PlayerQoEEvent] = []
        manager.onQoEEvent = { events.append($0) }
        let observer = NotificationCenter.default.addObserver(
            forName: .PlayerKitDidFail,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                manager.tearDown()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            manager.tearDown()
            manager.onQoEEvent = nil
        }

        manager.load(
            playerItem: PlayerItem(
                title: "Movie",
                url: URL(string: "https://example.com/movie.m3u8")!
            )
        )
        backend.lifecycleReporter?.playerDidFail(with: .mediaLoadFailed("backend detail"))

        XCTAssertEqual(events, [
            .loadRequested(autoplay: true),
            .fatalError,
            .exited,
        ])
    }
}

@MainActor
private final class QoEMockPlayer: PlayerProtocol, PlayerEventSource, PlayerStateSource {
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
    var onRuntimeStateChange: ((PlayerRuntimeState) -> Void)?

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
    func seek(to time: Double, completion: (@MainActor (Bool) -> Void)?) {
        currentTime = time
        completion?(true)
    }
    func scrubForward(by seconds: TimeInterval) { currentTime += seconds }
    func scrubBackward(by seconds: TimeInterval) { currentTime -= seconds }
    func load(url: URL, lastPosition: Double?) { currentTime = lastPosition ?? 0 }
    func selectAudioTrack(withID id: String) {}
    func selectSubtitle(withID id: String?) {}
    func getPlayerView() -> PKView { AVPlayerView() }
    func setupPiP() {}
    func startPiP() {}
    func stopPiP() {}
    func handlePinchGesture(scale: CGFloat) {}
    func setGravityToDefault() {}
    func setGravityToFill() {}
    func fetchStreamingInfo() -> StreamingInfo { .placeholder }
    func startRuntimeStateUpdates() {}
    func stopRuntimeStateUpdates() {}

    func emitRuntime(isPlaying: Bool, isBuffering: Bool) {
        self.isPlaying = isPlaying
        self.isBuffering = isBuffering
        onRuntimeStateChange?(
            PlayerRuntimeState(
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                currentTime: currentTime,
                duration: duration,
                bufferedDuration: bufferedDuration
            )
        )
    }
}
