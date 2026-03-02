import XCTest
@testable import PlayerKit

final class PlayerKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlayerManager.shared.resetPlayer()
        PlayerManager.shared.clearError()
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
}
