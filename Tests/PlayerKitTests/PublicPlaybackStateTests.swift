import Combine
import XCTest

// Deliberately NOT `@testable`. This file exercises PlayerKit exactly as a host
// application sees it, which is the only way to catch an access level
// regressing: under `@testable` every `internal` declaration is visible, so a
// property silently reverting from `public` to `internal` would still compile
// in every other test file in this target.
import PlayerKit

/// A host must be able to observe playback state without reaching into
/// `Player.playerManager` internals.
///
/// Before this, `isPlaying`, `isBuffering`, `duration`, `bufferedDuration`,
/// `availableAudioTracks`, `availableSubtitles`, `selectedAudio` and
/// `selectedSubtitle` were all `internal`, so an application literally could
/// not ask the library whether it was playing.
final class PublicPlaybackStateTests: XCTestCase {

    /// Every promoted property is readable from outside the module.
    ///
    /// The assertions matter less than the fact that these lines compile: an
    /// access-level regression is a build failure here.
    func testPlaybackStateIsReadableFromOutsideTheModule() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        let isPlaying: Bool = manager.isPlaying
        let isBuffering: Bool = manager.isBuffering
        let isPiPActive: Bool = manager.isPiPActive
        let isVideoEnded: Bool = manager.isVideoEnded
        let duration: Double = manager.duration
        let bufferedDuration: Double = manager.bufferedDuration
        let currentTime: Double = manager.currentTime
        let audioTracks: [TrackInfo] = manager.availableAudioTracks
        let subtitles: [TrackInfo] = manager.availableSubtitles
        let selectedAudio: TrackInfo? = manager.selectedAudio
        let selectedSubtitle: TrackInfo? = manager.selectedSubtitle

        XCTAssertFalse(isPlaying)
        XCTAssertFalse(isBuffering)
        XCTAssertFalse(isPiPActive)
        XCTAssertFalse(isVideoEnded)
        XCTAssertGreaterThanOrEqual(duration, 0)
        XCTAssertGreaterThanOrEqual(bufferedDuration, 0)
        XCTAssertGreaterThanOrEqual(currentTime, 0)
        XCTAssertTrue(audioTracks.isEmpty)
        XCTAssertTrue(subtitles.isEmpty)
        XCTAssertNil(selectedAudio)
        XCTAssertNil(selectedSubtitle)
    }

    /// The properties are `@Published`, so a host can drive SwiftUI or Combine
    /// from them. The projected value must be public too, not just the getter.
    func testPlaybackStateIsObservableFromOutsideTheModule() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        var cancellables: Set<AnyCancellable> = []
        let received = expectation(description: "publishers deliver current value")
        received.expectedFulfillmentCount = 4

        manager.$isPlaying.sink { _ in received.fulfill() }.store(in: &cancellables)
        manager.$isBuffering.sink { _ in received.fulfill() }.store(in: &cancellables)
        manager.$duration.sink { _ in received.fulfill() }.store(in: &cancellables)
        manager.$availableAudioTracks.sink { _ in received.fulfill() }.store(in: &cancellables)

        wait(for: [received], timeout: 5)
        cancellables.removeAll()
    }

    /// `TrackInfo` has to be usable, not merely visible: a host renders these
    /// in a list and compares one against the current selection.
    func testTrackInfoIsUsableFromOutsideTheModule() {
        let track = TrackInfo(id: "aud-1", name: "English", languageCode: "en")
        let same = TrackInfo(id: "aud-1", name: "English", languageCode: "en")
        let other = TrackInfo(id: "aud-2", name: "Uzbek", languageCode: "uz")

        // Identifiable — what ForEach needs.
        XCTAssertEqual(track.id, "aud-1")
        // Equatable — what comparing against selectedAudio needs.
        XCTAssertEqual(track, same)
        XCTAssertNotEqual(track, other)
        // Hashable — what Set/dictionary-keyed selection needs.
        XCTAssertEqual(Set([track, same, other]).count, 2)
    }

    /// The promoted properties are read-only to a host. This cannot be written
    /// as a compiling negative assertion, so it is recorded here as the
    /// intended contract: `manager.isPlaying = true` must not compile from
    /// outside the module, while the module and its tests can still write it.
    func testPromotedPropertiesExposeNoPublicSetter() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        // Reading is public; writing is `internal(set)` and unavailable here.
        XCTAssertFalse(manager.isPlaying)
    }
}
