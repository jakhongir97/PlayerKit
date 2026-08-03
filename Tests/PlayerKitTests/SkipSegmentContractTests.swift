import XCTest
@testable import PlayerKit

@MainActor
final class SkipSegmentContractTests: XCTestCase {
    func testBackendSkipMarkerValidationAndExactResolutionContract() throws {
        XCTAssertNil(PlayerSkipSegment(kind: .intro, startTime: -1, endTime: 20))
        XCTAssertNil(PlayerSkipSegment(kind: .intro, startTime: .nan, endTime: 20))
        XCTAssertNil(PlayerSkipSegment(kind: .intro, startTime: 10, endTime: .infinity))
        XCTAssertNil(PlayerSkipSegment(kind: .intro, startTime: 10, endTime: 10))
        XCTAssertNil(PlayerSkipSegment(kind: .intro, startTime: 10, endTime: 20, targetTime: .nan))
        XCTAssertNil(PlayerSkipSegment(kind: .intro, startTime: 10, endTime: 20, targetTime: 10))

        let intro = try XCTUnwrap(
            PlayerSkipSegment(kind: .intro, startTime: 30, endTime: 90)
        )
        let credits = try XCTUnwrap(
            PlayerSkipSegment(kind: .credits, startTime: 540, endTime: 600, targetTime: 605)
        )
        XCTAssertEqual(intro.targetTime, 90)

        let item = PlayerItem(
            title: "Episode",
            url: URL(string: "https://example.com/episode.m3u8")!,
            episodeIndex: 1,
            skipSegments: [intro, credits]
        )
        XCTAssertEqual(
            ExactSkipSegmentState.resolve(
                kind: .intro,
                segments: item.skipSegments,
                currentTime: 45
            ),
            .active(intro)
        )
        XCTAssertEqual(
            ExactSkipSegmentState.resolve(
                kind: .intro,
                segments: item.skipSegments,
                currentTime: 10
            ),
            .inactive,
            "An inactive exact marker must suppress heuristic fallback."
        )
        XCTAssertEqual(
            ExactSkipSegmentState.resolve(
                kind: .credits,
                segments: item.skipSegments,
                currentTime: 550
            ),
            .active(credits)
        )

        let unmarkedItem = PlayerItem(
            title: "Episode",
            url: URL(string: "https://example.com/unmarked.m3u8")!,
            episodeIndex: 2
        )
        XCTAssertTrue(unmarkedItem.skipSegments.isEmpty)
        XCTAssertEqual(
            ExactSkipSegmentState.resolve(
                kind: .intro,
                segments: unmarkedItem.skipSegments,
                currentTime: 45
            ),
            .absent,
            "Only an absent exact marker permits heuristic fallback."
        )
    }

    func testPlayerItemRebuildPreservesExactMarkers() throws {
        let intro = try XCTUnwrap(
            PlayerSkipSegment(kind: .intro, startTime: 30, endTime: 90)
        )
        let item = PlayerItem(
            title: "Episode",
            url: URL(string: "https://example.com/episode.m3u8")!,
            episodeIndex: 1,
            skipSegments: [intro]
        )

        let rebuilt = PlayerManager.shared.makePlayerItemCopy(
            from: item,
            resumePosition: 45
        )

        XCTAssertEqual(rebuilt.skipSegments, [intro])
        XCTAssertEqual(rebuilt.lastPosition, 45)
    }
}
