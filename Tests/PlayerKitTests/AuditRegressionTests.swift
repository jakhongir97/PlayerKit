import AVFoundation
import XCTest
@testable import PlayerKit

/// Regression coverage for defects found in the full-codebase audit.
///
/// Each test names the behaviour that was wrong before, so a future change that
/// reintroduces it fails here rather than in a user's hands.
@MainActor
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

    // MARK: - Refcounted process-global resources

    /// Two holders, two releases, one actual release of the resource. This is
    /// the property `tearDown()` needed and did not have: it deactivated the
    /// audio session, dropped the wake lock and detached the controller
    /// handlers unconditionally, so dismissing an inline trailer would have
    /// taken all three away from a main player that was still on screen.
    func testResourceIsReleasedOnlyWhenTheLastOwnerLetsGo() {
        let ownership = SharedResourceOwnership()
        let first = NSObject()
        let second = NSObject()

        XCTAssertTrue(ownership.addOwner(first), "first owner must acquire")
        XCTAssertFalse(ownership.addOwner(second), "second owner must not re-acquire")
        XCTAssertEqual(ownership.ownerCount, 2)

        XCTAssertFalse(ownership.removeOwner(first), "resource still has a holder")
        XCTAssertTrue(ownership.isHeld)

        XCTAssertTrue(ownership.removeOwner(second), "last owner must release")
        XCTAssertFalse(ownership.isHeld)
        XCTAssertEqual(ownership.ownerCount, 0)
    }

    /// The acquisition sites are idempotent by design, so a repeated acquire
    /// must not require a matching extra release — which is what a plain
    /// integer count would have demanded.
    func testRepeatedAcquireByTheSameOwnerStillReleasesOnFirstRelease() {
        let ownership = SharedResourceOwnership()
        let owner = NSObject()

        XCTAssertTrue(ownership.addOwner(owner))
        XCTAssertFalse(ownership.addOwner(owner))
        XCTAssertFalse(ownership.addOwner(owner))
        XCTAssertEqual(ownership.ownerCount, 1)

        XCTAssertTrue(ownership.removeOwner(owner), "one release must be enough")
        XCTAssertFalse(ownership.isHeld)
    }

    /// `tearDown()` is documented as idempotent, so a repeated release must not
    /// report a second release — which a plain integer count would have done by
    /// going negative.
    func testRepeatedReleaseDoesNotReleaseTwice() {
        let ownership = SharedResourceOwnership()
        let owner = NSObject()
        ownership.addOwner(owner)

        XCTAssertTrue(ownership.removeOwner(owner))
        XCTAssertFalse(ownership.removeOwner(owner), "second release is a no-op")
        XCTAssertFalse(ownership.removeOwner(NSObject()), "unknown owner is a no-op")
        XCTAssertEqual(ownership.ownerCount, 0)
    }

    /// The audio session itself, through the manager rather than the primitive.
    func testAudioSessionIsDeactivatedOnceForTwoOwners() {
        let manager = AudioSessionManager.shared
        manager.ownership.removeAllOwners()
        let releasesBefore = manager.resourceReleaseCount

        let first = NSObject()
        let second = NSObject()
        manager.configureAudioSession(for: first)
        manager.configureAudioSession(for: second)
        XCTAssertTrue(manager.isSessionActive)

        manager.deactivateAudioSession(for: first)
        XCTAssertTrue(
            manager.isSessionActive,
            "the session must survive one of two owners going away"
        )
        XCTAssertEqual(manager.resourceReleaseCount, releasesBefore)

        manager.deactivateAudioSession(for: second)
        XCTAssertFalse(manager.isSessionActive)
        XCTAssertEqual(manager.resourceReleaseCount, releasesBefore + 1)

        // Idempotent teardown must not deactivate a session someone else took.
        manager.deactivateAudioSession(for: second)
        XCTAssertEqual(manager.resourceReleaseCount, releasesBefore + 1)
    }

    func testControllerHandlersAreReleasedOnceForTwoOwners() {
        let manager = GameControllerManager.shared
        manager.ownership.removeAllOwners()
        let releasesBefore = manager.resourceReleaseCount

        let first = NSObject()
        let second = NSObject()
        manager.attachControllerHandlers(for: first)
        manager.attachControllerHandlers(for: second)
        XCTAssertEqual(manager.ownership.ownerCount, 2)

        // There is only a detach to observe if a controller was connected to
        // attach to in the first place; test machines generally have none.
        let didAttach = manager.areHandlersAttached
        let expectedReleases = releasesBefore + (didAttach ? 1 : 0)

        manager.releaseControllerHandlers(for: first)
        XCTAssertTrue(
            manager.ownership.isHeld,
            "one of two owners going away must not detach the handlers"
        )
        XCTAssertEqual(manager.resourceReleaseCount, releasesBefore)
        XCTAssertEqual(manager.areHandlersAttached, didAttach)

        manager.releaseControllerHandlers(for: second)
        XCTAssertFalse(manager.ownership.isHeld)
        XCTAssertFalse(manager.areHandlersAttached)
        XCTAssertEqual(manager.resourceReleaseCount, expectedReleases)

        manager.releaseControllerHandlers(for: second)
        XCTAssertEqual(manager.resourceReleaseCount, expectedReleases)
    }

    @MainActor
    func testWakeLockIsDroppedOnceForTwoOwners() {
        let coordinator = PlaybackWakeLockCoordinator.shared
        coordinator.ownership.removeAllOwners()
        let releasesBefore = coordinator.resourceReleaseCount

        let first = NSObject()
        let second = NSObject()
        coordinator.setPlaybackActive(true, for: first)
        coordinator.setPlaybackActive(true, for: second)
        XCTAssertEqual(coordinator.ownership.ownerCount, 2)

        coordinator.setPlaybackActive(false, for: first)
        XCTAssertEqual(
            coordinator.resourceReleaseCount,
            releasesBefore,
            "one player pausing must not let the screen sleep under another"
        )
        XCTAssertTrue(coordinator.ownership.isHeld)

        coordinator.setPlaybackActive(false, for: second)
        XCTAssertEqual(coordinator.resourceReleaseCount, releasesBefore + 1)
        XCTAssertFalse(coordinator.ownership.isHeld)

        coordinator.setPlaybackActive(false, for: second)
        XCTAssertEqual(coordinator.resourceReleaseCount, releasesBefore + 1)
    }

    /// Releasing must be driven by "nobody holds this any more", not by "the
    /// caller was the last registered owner".
    ///
    /// `GameControllerManager.init` attaches handlers to every already-connected
    /// controller without registering an owner, so a teardown that never
    /// acquired still has real work to do. Keying the detach on the release
    /// return value alone would skip it and leave PlayerKit's handlers on the
    /// host's controllers.
    func testControllerHandlersAreDetachedEvenIfTheReleaserNeverAcquired() {
        let manager = GameControllerManager.shared
        manager.ownership.removeAllOwners()

        // Simulate what init() does: handlers attached, nobody owning them.
        manager.attachControllerHandlers(for: NSObject())
        manager.ownership.removeAllOwners()
        guard manager.areHandlersAttached else {
            // No controller is connected on this machine, so there is nothing
            // to attach and nothing to assert.
            return
        }

        let releasesBefore = manager.resourceReleaseCount
        manager.releaseControllerHandlers(for: NSObject())

        XCTAssertFalse(manager.areHandlersAttached)
        XCTAssertEqual(manager.resourceReleaseCount, releasesBefore + 1)
    }

    /// The same property for the wake lock: a holder that was never registered
    /// must still be able to drop it.
    @MainActor
    func testWakeLockIsDroppedEvenIfTheReleaserNeverAcquired() {
        let coordinator = PlaybackWakeLockCoordinator.shared
        coordinator.ownership.removeAllOwners()

        coordinator.setPlaybackActive(true, for: NSObject())
        coordinator.ownership.removeAllOwners()
        XCTAssertTrue(coordinator.isHoldingWakeLock)

        let releasesBefore = coordinator.resourceReleaseCount
        coordinator.setPlaybackActive(false, for: NSObject())

        XCTAssertFalse(coordinator.isHoldingWakeLock)
        XCTAssertEqual(coordinator.resourceReleaseCount, releasesBefore + 1)
    }

    /// `PlayerManager.tearDown()` must hand back exactly what it took, and must
    /// not hand back what another owner is still holding.
    func testTearDownDoesNotReleaseAnotherOwnersAudioSession() {
        let audio = AudioSessionManager.shared
        audio.ownership.removeAllOwners()

        let manager = PlayerManager.shared
        manager.resetPlayer()

        let otherPlayer = NSObject()
        audio.configureAudioSession(for: otherPlayer)
        audio.configureAudioSession(for: manager)
        XCTAssertEqual(audio.ownership.ownerCount, 2)

        manager.tearDown()

        XCTAssertTrue(
            audio.isSessionActive,
            "tearing one player down must leave the other player's session active"
        )
        XCTAssertEqual(audio.ownership.ownerCount, 1)

        audio.deactivateAudioSession(for: otherPlayer)
        XCTAssertFalse(audio.isSessionActive)
    }

    // MARK: - Now playing

    /// The lock screen is process-global, so it is refcounted exactly like the
    /// audio session and the controller handlers.
    @MainActor
    func testNowPlayingCommandsAreReleasedOnceForTwoOwners() {
        let coordinator = NowPlayingCoordinator.shared
        coordinator.ownership.removeAllOwners()
        let releasesBefore = coordinator.resourceReleaseCount

        let first = NSObject()
        let second = NSObject()
        coordinator.installCommands(for: first, commands: Self.noopCommands)
        coordinator.installCommands(for: second, commands: Self.noopCommands)
        XCTAssertTrue(coordinator.areCommandsInstalled)
        XCTAssertEqual(coordinator.ownership.ownerCount, 2)

        coordinator.releaseCommands(for: first)
        XCTAssertTrue(
            coordinator.areCommandsInstalled,
            "one of two owners going away must not take the lock screen away"
        )
        XCTAssertEqual(coordinator.resourceReleaseCount, releasesBefore)

        coordinator.releaseCommands(for: second)
        XCTAssertFalse(coordinator.areCommandsInstalled)
        XCTAssertEqual(coordinator.resourceReleaseCount, releasesBefore + 1)

        coordinator.releaseCommands(for: second)
        XCTAssertEqual(coordinator.resourceReleaseCount, releasesBefore + 1)
    }

    /// `MPNowPlayingInfoCenter` extrapolates elapsed time from the rate and the
    /// moment of the last push, so republishing an unchanged state — which the
    /// 2 Hz runtime tick would do — repeatedly resets that interpolation.
    @MainActor
    func testUnchangedSnapshotIsNotRepublished() {
        let coordinator = NowPlayingCoordinator.shared
        coordinator.ownership.removeAllOwners()
        let owner = NSObject()
        coordinator.installCommands(for: owner, commands: Self.noopCommands)
        defer { coordinator.releaseCommands(for: owner) }

        let snapshot = NowPlayingSnapshot(
            title: "Fixture",
            subtitle: nil,
            duration: 600,
            elapsed: 10,
            rate: 1,
            isLive: false
        )
        coordinator.publish(snapshot)
        XCTAssertEqual(coordinator.lastPublishedSnapshot, snapshot)

        var moved = snapshot
        moved.elapsed = 20
        coordinator.publish(moved)
        XCTAssertEqual(coordinator.lastPublishedSnapshot, moved)
    }

    /// A live stream has no total, and publishing 0 renders a zero-length
    /// scrubber instead of hiding it.
    func testLiveSnapshotHasNoDurationAndIsMarkedLive() {
        let (manager, player) = makeLiveManager(currentTime: 5000)
        defer { manager.tearDown() }
        withExtendedLifetime(player) {
            manager.load(
                playerItem: PlayerItem(
                    title: "Channel 1",
                    url: URL(string: "https://example.com/live.m3u8")!
                )
            )
            manager.duration = 0
            manager.currentTime = 5000

            let snapshot = manager.makeNowPlayingSnapshot()
            XCTAssertEqual(snapshot?.title, "Channel 1")
            XCTAssertNil(snapshot?.duration, "live must not advertise a total")
            XCTAssertEqual(snapshot?.isLive, true)
        }
    }

    /// `playbackSpeed` keeps its configured value while paused, so reporting it
    /// directly would animate a stopped playhead on the lock screen.
    func testPausedSnapshotReportsZeroRate() {
        let manager = PlayerManager.shared
        manager.resetPlayer()
        defer { manager.tearDown() }

        manager.load(
            playerItem: PlayerItem(
                title: "Fixture",
                url: URL(string: "https://example.com/movie.m3u8")!
            )
        )
        manager.setPlaybackSpeed(1.5)
        manager.isPlaying = false

        XCTAssertEqual(manager.playbackSpeed, 1.5)
        XCTAssertEqual(manager.makeNowPlayingSnapshot()?.rate, 0)

        manager.isPlaying = true
        XCTAssertEqual(manager.makeNowPlayingSnapshot()?.rate, 1.5)
    }

    /// Background continuation relaxes the capture-protection posture, so it
    /// must default to the old behaviour and survive a reload.
    func testBackgroundPlaybackIsOffByDefaultAndSurvivesPlayerCreation() {
        let manager = PlayerManager.shared
        manager.resetPlayer()
        defer { manager.tearDown() }

        XCTAssertFalse(manager.isBackgroundPlaybackEnabled)

        manager.isBackgroundPlaybackEnabled = true
        manager.setPlayer(type: .avPlayer)

        let wrapper = manager.currentPlayer as? AVPlayerWrapper
        XCTAssertEqual(
            wrapper?.allowsBackgroundPlayback,
            true,
            "the preference must reach a backend created after it was set"
        )
    }

    private static let noopCommands = NowPlayingCommands(
        play: {},
        pause: {},
        toggle: {},
        skipForward: { _ in },
        skipBackward: { _ in },
        seek: { _ in },
        canSeek: { true },
        next: {},
        canNext: { false },
        previous: {},
        canPrevious: { false }
    )

    // MARK: - Mute and autoplay

    /// Every backend could already mute; nothing exposed it. Setting it before
    /// any media exists must still take effect, which is why the preference is
    /// stored rather than proxied through `currentPlayer`.
    func testMutePreferenceReachesABackendCreatedAfterItWasSet() {
        let manager = PlayerManager.shared
        manager.resetPlayer()
        defer {
            manager.isMuted = false
            manager.tearDown()
        }

        XCTAssertFalse(manager.isMuted)
        manager.isMuted = true
        manager.setPlayer(type: .avPlayer)

        XCTAssertTrue(manager.isMuted)
        XCTAssertEqual((manager.currentPlayer as? AVPlayerWrapper)?.isMuted, true)
    }

    func testMuteAppliesToAnAlreadyRunningBackend() {
        let manager = PlayerManager.shared
        manager.resetPlayer()
        manager.setPlayer(type: .avPlayer)
        defer {
            manager.isMuted = false
            manager.tearDown()
        }

        manager.isMuted = true
        XCTAssertEqual((manager.currentPlayer as? AVPlayerWrapper)?.isMuted, true)

        manager.isMuted = false
        XCTAssertEqual((manager.currentPlayer as? AVPlayerWrapper)?.isMuted, false)
    }

    /// Autoplay defaults to on, which is what every existing host already gets.
    func testAutoplayDefaultsToOnAndLoadRequestsPlayback() {
        let manager = PlayerManager.shared
        manager.resetPlayer()
        defer { manager.tearDown() }

        XCTAssertTrue(manager.autoplay)
        manager.setPlayer(type: .avPlayer)
        manager.load(
            playerItem: PlayerItem(
                title: "Fixture",
                url: URL(string: "https://example.com/movie.m3u8")!
            )
        )

        // isPlaying is transient here — a real AVPlayerWrapper's runtime-state
        // observer overwrites it once the fixture URL fails to load.
        // isPlaybackRequested is the durable intent the resume ladder reads.
        XCTAssertTrue(manager.isPlaybackRequested)
    }

    /// With autoplay off, `load` prepares the item without requesting playback.
    /// `isPlaybackRequested` is what the resume ladder consults, so leaving it
    /// true would have AVFoundation start on its own once the item was ready.
    func testAutoplayOffLoadsWithoutRequestingPlayback() {
        let manager = PlayerManager.shared
        manager.resetPlayer()
        manager.autoplay = false
        defer {
            manager.autoplay = true
            manager.tearDown()
        }

        manager.setPlayer(type: .avPlayer)
        manager.load(
            playerItem: PlayerItem(
                title: "Fixture",
                url: URL(string: "https://example.com/movie.m3u8")!
            )
        )

        XCTAssertFalse(manager.isPlaybackRequested)
    }

    func testOnlyMediaLoadsAreCancelledWhenTheLocalPlayerDetaches() {
        XCTAssertTrue(CastPendingRequestKind.mediaLoad.cancelsWhenPlayerDetaches)
        XCTAssertFalse(CastPendingRequestKind.stop.cancelsWhenPlayerDetaches)
    }

    // MARK: - Ordinary playback

    /// Kept from the deleted DubberDisabledTests, where it guarded ordinary
    /// playback against the dormant dub machinery. It still earns its place:
    /// `load(playerItem:)` used to run a dub-workflow cancellation before
    /// storing the item, and that call site was removed with Dubber.
    @MainActor
    func testLoadStoresTheItemAndReportsNoError() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }

        let item = PlayerItem(
            title: "Fixture",
            url: URL(string: "https://example.com/index.m3u8")!
        )
        manager.load(playerItem: item)

        XCTAssertEqual(manager.playerItem?.url, item.url)
        XCTAssertNil(manager.lastError)
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

    func seek(to time: Double, completion: (@MainActor (Bool) -> Void)?) {
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
