#if os(macOS)
import AVFoundation
import XCTest
@testable import PlayerKit

final class PlaybackDiagnosticsLogCacheTests: XCTestCase {
    func testCacheRejectsStaleGenerationAndWrongItem() {
        let cache = PlaybackDiagnosticsLogCache()
        let firstItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let secondItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/zero"))
        let firstToken = cache.begin(for: firstItem)
        let firstSnapshot = snapshot(playbackType: "VOD", errorCode: 41)

        XCTAssertTrue(cache.commit(firstSnapshot, token: firstToken))
        XCTAssertEqual(cache.snapshot(for: firstItem), firstSnapshot)
        XCTAssertEqual(cache.snapshot(for: secondItem), .empty)

        let secondToken = cache.begin(for: secondItem)
        let secondSnapshot = snapshot(playbackType: "LIVE", errorCode: 42)

        XCTAssertFalse(cache.commit(firstSnapshot, token: firstToken))
        XCTAssertEqual(cache.snapshot(for: firstItem), .empty)
        XCTAssertEqual(cache.snapshot(for: secondItem), .empty)
        XCTAssertTrue(cache.commit(secondSnapshot, token: secondToken))
        XCTAssertEqual(cache.snapshot(for: secondItem), secondSnapshot)

        cache.invalidate()
        XCTAssertEqual(cache.snapshot(for: secondItem), .empty)
        XCTAssertFalse(cache.commit(secondSnapshot, token: secondToken))
    }

    func testPlaybackCallbackIdentityRequiresExactSessionAndItem() {
        let sessionID = UUID()
        let currentItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
        let replacedItem = AVPlayerItem(url: URL(fileURLWithPath: "/dev/zero"))

        XCTAssertTrue(
            playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: sessionID,
                currentSessionID: sessionID,
                capturedItem: currentItem,
                currentItem: currentItem
            )
        )
        XCTAssertFalse(
            playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: sessionID,
                currentSessionID: sessionID,
                capturedItem: replacedItem,
                currentItem: currentItem
            )
        )
        XCTAssertFalse(
            playbackHealthCallbackBelongsToCurrentSession(
                capturedSessionID: sessionID,
                currentSessionID: UUID(),
                capturedItem: currentItem,
                currentItem: currentItem
            )
        )
    }

    private func snapshot(
        playbackType: String,
        errorCode: Int
    ) -> PlaybackDiagnosticsLogCacheSnapshot {
        PlaybackDiagnosticsLogCacheSnapshot(
            network: .aggregatingAccessLogPeriods([]),
            playbackType: playbackType,
            errorLogEventCount: 1,
            recentErrors: [
                PlaybackDiagnosticsError(
                    occurredAt: Date(timeIntervalSince1970: 1),
                    domain: NSURLErrorDomain,
                    code: errorCode
                )
            ]
        )
    }
}
#endif
