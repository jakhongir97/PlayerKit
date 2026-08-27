import CoreGraphics
import SwiftUI
import XCTest
@testable import PlayerKit

/// The top bar's host slot and its compact arrangement.
///
/// Both exist because of one screenshot: an iPhone in portrait with the host's
/// own "more" button drawn over PlayerKit's info disc, and the title beside
/// them truncated to three letters. The host button was pinned 124pt from the
/// trailing edge — right for one historical bar, wrong for the next — and the
/// title had ~50pt because six discs do not leave more on a 370pt line.
@MainActor
final class HostActionsAndTopBarTests: XCTestCase {

    // MARK: - Geometry

    /// iPhone 17 Pro: 402pt wide in portrait, 874 in landscape with 62pt
    /// side insets. The content inset tracks width, so the bar sees these.
    private var phonePortraitContentWidth: CGFloat {
        402 - (PlayerChromeMetrics.contentInset(for: 402) * 2)
    }

    private var phoneLandscapeContentWidth: CGFloat {
        let safeWidth: CGFloat = 874 - (62 * 2)
        return safeWidth - (PlayerChromeMetrics.contentInset(for: safeWidth) * 2)
    }

    func testTrailingClusterWidthCountsEveryDiscAtItsHitTarget() {
        XCTAssertEqual(TopControlsView.trailingClusterWidth(controlCount: 0), 0)
        XCTAssertEqual(
            TopControlsView.trailingClusterWidth(controlCount: 1),
            PlayerChromeMetrics.minimumHitTarget
        )
        XCTAssertEqual(
            TopControlsView.trailingClusterWidth(controlCount: 5),
            (PlayerChromeMetrics.minimumHitTarget * 5) + (PlayerChromeMetrics.spacingS * 4)
        )
    }

    /// The compact bar carries options and lock, so an iPhone in portrait has
    /// room for the title on the same line.
    func testCompactBarKeepsTheTitleInlineOnAPhoneInBothOrientations() {
        let shipping = 2
        XCTAssertEqual(
            TopControlsView.arrangement(
                availableWidth: phonePortraitContentWidth,
                trailingControlCount: shipping
            ),
            .inline
        )
        XCTAssertEqual(
            TopControlsView.arrangement(
                availableWidth: phoneLandscapeContentWidth,
                trailingControlCount: shipping
            ),
            .inline
        )
        XCTAssertGreaterThanOrEqual(
            TopControlsView.inlineTitleWidth(
                availableWidth: phonePortraitContentWidth,
                trailingControlCount: shipping
            ),
            TopControlsView.minimumInlineTitleWidth
        )
    }

    func testDirectActionCountIncludesRoutesBackendOptionsAndLock() {
        XCTAssertEqual(
            TopControlsView.directTrailingControlCount(
                hasCast: true,
                hasAirPlay: true,
                hasAlternativeEngine: true
            ),
            5
        )
        XCTAssertEqual(
            TopControlsView.directTrailingControlCount(
                hasCast: false,
                hasAirPlay: true,
                hasAlternativeEngine: true
            ),
            4
        )
    }

    /// Route and backend controls remain directly discoverable whenever the
    /// title can keep its minimum readable width. Only compact surfaces fold
    /// them into the options panel.
    func testPrimaryActionsStayDirectWhenTheyFitAndCompactWhenTheyDoNot() {
        let directControlCount = 5

        XCTAssertEqual(
            TopControlsView.actionPresentation(
                availableWidth: phonePortraitContentWidth,
                directControlCount: directControlCount
            ),
            .compact
        )
        XCTAssertEqual(
            TopControlsView.actionPresentation(
                availableWidth: phoneLandscapeContentWidth,
                directControlCount: directControlCount
            ),
            .direct
        )
        XCTAssertEqual(
            TopControlsView.actionPresentation(
                availableWidth: 1_000,
                directControlCount: directControlCount
            ),
            .direct
        )
    }

    func testPlayerSwitcherIsShownWheneverAnotherBackendExists() {
        XCTAssertFalse(TopControlsView.showsPlayerSwitcher(supportedPlayerCount: 1))
        XCTAssertTrue(TopControlsView.showsPlayerSwitcher(supportedPlayerCount: 2))
    }

    /// The direct row — Cast, AirPlay, backend, options and lock — is what the
    /// compact fallback exists for.
    func testTitleGetsItsOwnLineWhenTheTrailingEdgeIsCrowded() {
        let releaseTrailingCount = 5

        let portraitTitleWidth = TopControlsView.inlineTitleWidth(
            availableWidth: phonePortraitContentWidth,
            trailingControlCount: releaseTrailingCount
        )
        XCTAssertLessThan(
            portraitTitleWidth,
            TopControlsView.minimumInlineTitleWidth,
            "An inline title would have \(portraitTitleWidth)pt — that is the 'Вен…' bug"
        )
        XCTAssertEqual(
            TopControlsView.arrangement(
                availableWidth: phonePortraitContentWidth,
                trailingControlCount: releaseTrailingCount
            ),
            .stacked
        )

        XCTAssertEqual(
            TopControlsView.arrangement(
                availableWidth: phoneLandscapeContentWidth,
                trailingControlCount: releaseTrailingCount
            ),
            .inline
        )
        // Even a future sixth capability control still fits in landscape.
        XCTAssertEqual(
            TopControlsView.arrangement(
                availableWidth: phoneLandscapeContentWidth,
                trailingControlCount: releaseTrailingCount + 1
            ),
            .inline
        )
    }

    func testArrangementFlipsExactlyAtTheMinimumTitleWidth() {
        let count = 4
        let exact = PlayerChromeMetrics.minimumHitTarget
            + (PlayerChromeMetrics.spacingM * 2)
            + TopControlsView.trailingClusterWidth(controlCount: count)
            + TopControlsView.minimumInlineTitleWidth

        XCTAssertEqual(
            TopControlsView.arrangement(availableWidth: exact, trailingControlCount: count),
            .inline
        )
        XCTAssertEqual(
            TopControlsView.arrangement(availableWidth: exact - 1, trailingControlCount: count),
            .stacked
        )
    }

    /// An iPad in portrait and a Slide Over column, the two ends of the iPad
    /// range the bar has to survive.
    func testIPadWidthsInlineAndSlideOverStacks() {
        let padPortrait: CGFloat = 820 - (PlayerChromeMetrics.contentInset(for: 820) * 2)
        XCTAssertEqual(
            TopControlsView.arrangement(availableWidth: padPortrait, trailingControlCount: 5),
            .inline
        )
        let slideOver: CGFloat = 320 - (PlayerChromeMetrics.contentInset(for: 320) * 2)
        XCTAssertEqual(
            TopControlsView.arrangement(availableWidth: slideOver, trailingControlCount: 5),
            .stacked
        )
    }

    /// 320pt — the narrowest iPhone in portrait, and an iPad Slide Over column
    /// — cannot hold the shipping cluster at the ordinary 8pt gap. The gap
    /// gives way before the discs do, because they are already at the minimum
    /// touch target.
    func testTrailingClusterTightensItsGapBeforeItCanOverflow() {
        let narrow: CGFloat = 320 - (PlayerChromeMetrics.contentInset(for: 320) * 2)
        // Cast, AirPlay, backend, options and lock: the full direct cluster.
        let releaseCount = 5

        XCTAssertGreaterThan(
            TopControlsView.trailingClusterWidth(controlCount: releaseCount),
            narrow - PlayerChromeMetrics.minimumHitTarget - PlayerChromeMetrics.spacingM,
            "Precondition: the relaxed gap is what overflowed"
        )

        let spacing = TopControlsView.clusterSpacing(
            availableWidth: narrow,
            trailingControlCount: releaseCount
        )
        XCTAssertEqual(spacing, PlayerChromeMetrics.spacingXS)

        let cluster = TopControlsView.trailingClusterWidth(
            controlCount: releaseCount,
            spacing: spacing
        )
        let budget = narrow - PlayerChromeMetrics.minimumHitTarget - PlayerChromeMetrics.spacingM
        XCTAssertLessThanOrEqual(cluster, budget, "The lock must stay inside the content width")

        // A surface with room keeps the relaxed gap.
        XCTAssertEqual(
            TopControlsView.clusterSpacing(availableWidth: 800, trailingControlCount: releaseCount),
            PlayerChromeMetrics.spacingS
        )
    }

    // MARK: - Playback that has run out

    /// With the ended overlay suppressed by policy — trailers, live, the
    /// embedded TV transport — a finished item left a frozen frame and a play
    /// button that did nothing, because the backend sits at the end and
    /// ignores `play()`.
    func testTappingPlayOnAFinishedItemRestartsIt() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        manager.playerItem = PlayerItem(
            title: "Trailer",
            url: URL(string: "https://example.com/t.m3u8")!
        )
        manager.videoDidEnd()
        XCTAssertTrue(manager.isVideoEnded)

        manager.userDidTogglePlayback()
        XCTAssertFalse(manager.isVideoEnded, "the play control on a finished item must restart it")
    }

    /// …but only from the control. `play()` is also how an ended audio-session
    /// interruption, a Now Playing command and a queue load resume, and none of
    /// those asked to restart a finished film from zero.
    ///
    /// Needs a backend installed: with none, `play()` restores one, and that
    /// path clears `isVideoEnded` on its own — which would make this pass for
    /// the wrong reason.
    func testPlainPlayDoesNotRestartAFinishedItem() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        let backend = FinishedPlaybackMockPlayer()
        manager.installPlayerBackend(backend)
        manager.playerItem = PlayerItem(
            title: "Movie",
            url: URL(string: "https://example.com/m.m3u8")!
        )
        manager.videoDidEnd()
        XCTAssertTrue(manager.isVideoEnded)
        backend.loadedURLs.removeAll()

        manager.play()
        XCTAssertTrue(
            manager.isVideoEnded,
            "A background resume must leave a finished item finished"
        )
        XCTAssertTrue(
            backend.loadedURLs.isEmpty,
            "A background resume must not reload the item from the start"
        )
    }

    // MARK: - The host slot

    func testHostActionsAreOfferedOnlyWhenThereIsSomethingToShow() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        manager.hostActions = []

        let bar = TopControlsView(playerManager: manager, availableWidth: 1000)
        XCTAssertFalse(bar.showsHostActions)

        // A submenu with nothing in it is not something to show.
        manager.hostActions = [.submenu(id: "empty", title: "Empty", children: [])]
        XCTAssertFalse(bar.showsHostActions)

        manager.hostActions = [
            .submenu(id: "empty", title: "Empty", children: []),
            PlayerHostAction(id: "share", title: "Share", systemImage: "square.and.arrow.up") {},
        ]
        XCTAssertTrue(bar.showsHostActions)
        XCTAssertEqual(manager.hostActions.presentable.map(\.id), ["share"])

        // Whatever the host contributes, the bar's own width does not move:
        // its rows live inside the options panel, not on the bar.
        XCTAssertEqual(bar.trailingControlCount, 2)
    }

    /// The lock is the only way out of a locked player, so it can never be a
    /// row inside a panel that the lock itself would hide.
    func testLockStaysOutsideTheOptionsControl() {
        let manager = PlayerManager.shared
        defer {
            manager.isLocked = false
            manager.tearDown()
        }
        let bar = TopControlsView(playerManager: manager, availableWidth: 1000)

        manager.areControlsVisible = true
        manager.isLocked = true
        XCTAssertFalse(bar.showsChrome, "The options control goes with the chrome")
        XCTAssertTrue(bar.showsUnlockControl, "The lock does not")
    }

    func testNestedSubmenusArePresentableOnlyThroughARealLeaf() {
        let leaf = PlayerHostAction(id: "leaf", title: "Leaf") {}
        let nested = PlayerHostAction.submenu(
            id: "outer",
            title: "Outer",
            children: [.submenu(id: "inner", title: "Inner", children: [leaf])]
        )
        XCTAssertTrue(nested.isPresentable)

        let hollow = PlayerHostAction.submenu(
            id: "outer",
            title: "Outer",
            children: [.submenu(id: "inner", title: "Inner", children: [])]
        )
        XCTAssertFalse(hollow.isPresentable)
    }

    func testHostActionRunsItsHandlerOnTheMainActor() {
        var fired = 0
        let action = PlayerHostAction(id: "a", title: "A") { fired += 1 }
        guard case .action(let handler) = action.kind else {
            return XCTFail("Expected a plain action")
        }
        handler()
        XCTAssertEqual(fired, 1)
        XCTAssertTrue(action.isEnabled)
    }

    /// A torn-down manager is handed to the next host; it must not carry the
    /// previous screen's report/share rows into that session.
    func testTearDownClearsHostActions() {
        let manager = PlayerManager.shared
        manager.hostActions = [PlayerHostAction(id: "share", title: "Share") {}]
        XCTAssertFalse(manager.hostActions.isEmpty)

        manager.tearDown()
        XCTAssertTrue(manager.hostActions.isEmpty)
    }

    /// The host slot obeys the same gating as every other disc: gone with the
    /// chrome, gone under the lock, while the unlock stays.
    func testHostActionsFollowChromeGatingNotTheLock() {
        let manager = PlayerManager.shared
        defer {
            manager.isLocked = false
            manager.tearDown()
        }
        manager.hostActions = [PlayerHostAction(id: "share", title: "Share") {}]
        let bar = TopControlsView(playerManager: manager, availableWidth: 1000)

        manager.areControlsVisible = true
        manager.isLocked = false
        XCTAssertTrue(bar.showsChrome)
        XCTAssertTrue(bar.showsHostActions)

        manager.isLocked = true
        XCTAssertFalse(bar.showsChrome, "The overflow disc is chrome; it goes with the lock")
        XCTAssertTrue(bar.showsUnlockControl)
    }
}


/// The smallest backend that lets `play()` run without the manager restoring
/// one for it.
@MainActor
private final class FinishedPlaybackMockPlayer: PlayerProtocol, PlayerEventSource {
    var isPlaying = false
    var playbackSpeed: Float = 1
    var currentTime: Double = 120
    var duration: Double = 120
    var bufferedDuration: Double = 120
    var isBuffering = false
    var availableAudioTracks: [TrackInfo] = []
    var availableSubtitles: [TrackInfo] = []
    var currentAudioTrack: TrackInfo?
    var currentSubtitleTrack: TrackInfo?
    var lifecycleReporter: PlayerLifecycleReporting?
    var loadedURLs: [URL] = []

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
    func seek(to time: Double, completion: (@MainActor (Bool) -> Void)?) {
        currentTime = time
        completion?(true)
    }
    func scrubForward(by seconds: TimeInterval) { currentTime += seconds }
    func scrubBackward(by seconds: TimeInterval) { currentTime -= seconds }
    func selectAudioTrack(withID id: String) {}
    func selectSubtitle(withID id: String?) {}
    func load(url: URL, lastPosition: Double?) {
        loadedURLs.append(url)
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
