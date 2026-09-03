import CoreGraphics
import XCTest
@testable import PlayerKit
#if os(macOS)
import AppKit
#endif

@MainActor
final class UIAuditRegressionTests: XCTestCase {
    func testPlaybackSpeedMenuMatchesStandardRateSet() {
        XCTAssertEqual(
            PlaybackSpeedMenu.supportedSpeeds,
            [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
        )
    }

    func testPlayerViewDefaultsToAutomaticTeardownAndAllowsHostOwnership() {
        let automatic = PlayerView(playerManager: .shared)
        let hostManaged = PlayerView(
            playerManager: .shared,
            automaticallyTearsDownOnDisappear: false
        )

        XCTAssertTrue(automatic.automaticallyTearsDownOnDisappear)
        XCTAssertFalse(hostManaged.automaticallyTearsDownOnDisappear)
    }

    func testPresentationPolicyDefaultsToFullChromeAndCanKeepEndedPlaybackNonblocking() {
        let defaults = PlayerPresentationPolicy()
        XCTAssertTrue(defaults.showsPlaybackSpeedControl)
        XCTAssertTrue(defaults.showsPlaybackQualityControl)
        XCTAssertTrue(defaults.showsPlaybackEndedOverlay)
        XCTAssertTrue(defaults.showsMediaTrackControls)

        let trailer = PlayerPresentationPolicy(
            showsPlaybackSpeedControl: false,
            showsPlaybackQualityControl: false,
            showsPlaybackEndedOverlay: false
        )
        let manager = PlayerManager.shared
        manager.isVideoEnded = true
        defer { manager.isVideoEnded = false }

        XCTAssertTrue(PlayerView(playerManager: manager).hasBlockingStatus)
        XCTAssertFalse(
            PlayerView(playerManager: manager, presentationPolicy: trailer).hasBlockingStatus
        )
        XCTAssertFalse(
            MediaOptionsMenu.hasVisibleOptions(
                presentationPolicy: trailer,
                hasPlaybackQualities: true,
                hasSubtitles: false,
                hasAudioTracks: false
            )
        )
        XCTAssertTrue(
            MediaOptionsMenu.hasVisibleOptions(
                presentationPolicy: trailer,
                hasPlaybackQualities: false,
                hasSubtitles: true,
                hasAudioTracks: false
            )
        )
    }

    #if os(macOS)
    func testHostingWindowProbeTracksAttachmentsWithoutForgettingTransientDetachment() {
        let firstWindow = NSWindow()
        let secondWindow = NSWindow()
        let reference = PlayerKitHostingWindowReference()
        var reportedWindows: [NSWindow] = []
        let probe = PlayerKitHostingWindowProbeView { window in
            reportedWindows.append(window)
            reference.window = window
        }

        firstWindow.contentView?.addSubview(probe)
        XCTAssertTrue(reportedWindows.last === firstWindow)
        XCTAssertTrue(reference.window === firstWindow)

        probe.removeFromSuperview()
        XCTAssertEqual(reportedWindows.count, 1)
        XCTAssertTrue(reference.window === firstWindow)

        secondWindow.contentView?.addSubview(probe)
        XCTAssertEqual(reportedWindows.count, 2)
        XCTAssertTrue(reportedWindows.last === secondWindow)
        XCTAssertTrue(reference.window === secondWindow)
    }

    func testFullscreenWindowOwnershipUsesCapturedStandaloneWindow() {
        let hostingWindow = NSWindow()

        XCTAssertTrue(
            PlayerKitMacWindowOwnership.fullscreenTarget(for: hostingWindow) === hostingWindow
        )
        XCTAssertNil(PlayerKitMacWindowOwnership.fullscreenTarget(for: nil))
    }

    func testCapturedSheetOwnershipIgnoresAnUnrelatedKeyWindowForFullscreen() {
        let parentWindow = NSWindow()
        let sheetWindow = NSWindow()
        // This models the unrelated key-window candidate that the old global
        // lookup selected; ownership resolution now has no global fallback.
        let unrelatedKeyWindow = NSWindow()
        parentWindow.beginSheet(sheetWindow)
        defer {
            if sheetWindow.sheetParent != nil {
                parentWindow.endSheet(sheetWindow)
            }
        }

        let fullscreenTarget = PlayerKitMacWindowOwnership.fullscreenTarget(for: sheetWindow)
        XCTAssertTrue(fullscreenTarget === parentWindow)
        XCTAssertFalse(fullscreenTarget === unrelatedKeyWindow)
        XCTAssertTrue(
            PlayerKitMacWindowOwnership.fullscreenNotificationTargets(
                Notification(name: NSWindow.willEnterFullScreenNotification, object: parentWindow),
                hostingWindow: sheetWindow
            )
        )
        XCTAssertFalse(
            PlayerKitMacWindowOwnership.fullscreenNotificationTargets(
                Notification(name: NSWindow.willEnterFullScreenNotification, object: unrelatedKeyWindow),
                hostingWindow: sheetWindow
            )
        )

    }

    func testFullscreenTransitionRejectsRapidSecondToggleAndUnlocksAfterCompletionOrTeardown() {
        var state = PlayerKitMacFullscreenTransitionState()

        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin())
        XCTAssertTrue(state.isInFlight)

        // AppKit did-enter/did-exit completion unlocks the next command.
        state.finish()
        XCTAssertFalse(state.isInFlight)
        XCTAssertTrue(state.begin())

        // A transient view teardown must unlock a preserved @State value too.
        state.finish()
        XCTAssertFalse(state.isInFlight)
        XCTAssertTrue(state.begin())
    }
    #endif

    func testMediaTrackPolicyDoesNotHideIndependentQualityControl() {
        let tracksHidden = PlayerPresentationPolicy(
            showsPlaybackSpeedControl: false,
            showsPlaybackQualityControl: false,
            showsMediaTrackControls: false
        )
        XCTAssertFalse(
            MediaOptionsMenu.hasVisibleOptions(
                presentationPolicy: tracksHidden,
                hasPlaybackQualities: false,
                hasSubtitles: true,
                hasAudioTracks: true
            )
        )
        XCTAssertFalse(tracksHidden.resolved(for: .pureLive).showsMediaTrackControls)

        let qualityVisible = PlayerPresentationPolicy(
            showsPlaybackSpeedControl: false,
            showsPlaybackQualityControl: true,
            showsMediaTrackControls: false
        )
        XCTAssertTrue(
            MediaOptionsMenu.hasVisibleOptions(
                presentationPolicy: qualityVisible,
                hasPlaybackQualities: true,
                hasSubtitles: true,
                hasAudioTracks: true
            )
        )
    }

    func testPlayerViewLoadIdentityFollowsEveryInputAndIsStableForNaN() {
        let url = URL(string: "https://example.com/video.m3u8")!
        let first = PlayerItem(title: "One", url: url, lastPosition: .nan, episodeIndex: 1)
        let renamed = PlayerItem(title: "Two", url: url, lastPosition: .nan, episodeIndex: 1)
        let live = PlayerItem(title: "One", url: url, timelineMode: .seekableLive, lastPosition: .nan, episodeIndex: 1)

        let firstIdentity = PlayerView.LoadMode.single(first).identity
        XCTAssertEqual(firstIdentity, PlayerView.LoadMode.single(first).identity)
        XCTAssertNotEqual(firstIdentity, PlayerView.LoadMode.single(renamed).identity)
        XCTAssertNotEqual(firstIdentity, PlayerView.LoadMode.single(live).identity)
        XCTAssertNotEqual(
            PlayerView.LoadMode.episodes([first], 0).identity,
            PlayerView.LoadMode.episodes([first], 1).identity
        )
    }

    func testExplicitPureLiveHidesTheScrubberWithoutChangingAutomaticLayout() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        let url = URL(string: "https://example.com/live.m3u8")!
        manager.areControlsVisible = true
        manager.isLocked = false

        manager.playerItem = PlayerItem(title: "Automatic", url: url)
        #if os(iOS)
        let automaticControls = PlayerControlsView(
            playerManager: manager,
            thumbnailPreviewController: WebVTTThumbnailPreviewController(),
            presentationPolicy: .init()
        )
        #else
        let automaticControls = PlayerControlsView(playerManager: manager, presentationPolicy: .init())
        #endif
        XCTAssertTrue(automaticControls.showsScrubber)

        manager.playerItem = PlayerItem(title: "Pure live", url: url, timelineMode: .pureLive)
        #if os(iOS)
        let liveControls = PlayerControlsView(
            playerManager: manager,
            thumbnailPreviewController: WebVTTThumbnailPreviewController(),
            presentationPolicy: .init()
        )
        #else
        let liveControls = PlayerControlsView(playerManager: manager, presentationPolicy: .init())
        #endif
        XCTAssertFalse(liveControls.showsScrubber)
    }

    func testExplicitLiveModesResolvePresentationAndMarkerPoliciesInternally() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        let url = URL(string: "https://example.com/live.m3u8")!
        let requested = PlayerPresentationPolicy()

        for mode in [PlayerTimelineMode.seekableLive, .pureLive] {
            manager.playerItem = PlayerItem(title: "Live", url: url, timelineMode: mode)
            let view = PlayerView(playerManager: manager, presentationPolicy: requested)

            XCTAssertEqual(
                view.effectivePresentationPolicy,
                PlayerPresentationPolicy(
                    showsPlaybackSpeedControl: false,
                    showsPlaybackQualityControl: true,
                    showsPlaybackEndedOverlay: false
                )
            )
            XCTAssertFalse(mode.allowsMarkerSkipActions)
            manager.isVideoEnded = true
            XCTAssertFalse(view.hasBlockingStatus)
            manager.isVideoEnded = false
        }

        XCTAssertEqual(requested.resolved(for: .automatic), requested)
        XCTAssertEqual(requested.resolved(for: .onDemand), requested)
        XCTAssertFalse(
            PlayerPresentationPolicy(showsPlaybackQualityControl: false)
                .resolved(for: .seekableLive)
                .showsPlaybackQualityControl
        )
        XCTAssertTrue(PlayerTimelineMode.automatic.allowsMarkerSkipActions)
        XCTAssertTrue(PlayerTimelineMode.onDemand.allowsMarkerSkipActions)
    }

    func testCompactLiveStatusGetsItsOwnConditionalRow() {
        let manager = PlayerManager.shared
        defer { manager.tearDown() }
        let url = URL(string: "https://example.com/live.m3u8")!

        manager.playerItem = PlayerItem(title: "Movie", url: url, timelineMode: .onDemand)
        XCTAssertFalse(
            BottomControlsView(playerManager: manager, presentationPolicy: .init())
                .showsCompactLiveStatusRow
        )

        manager.playerItem = PlayerItem(title: "Live", url: url, timelineMode: .pureLive)
        XCTAssertTrue(
            BottomControlsView(playerManager: manager, presentationPolicy: .init())
                .showsCompactLiveStatusRow
        )
    }

    func testMenuViewModelsDoNotRetainThemselvesThroughCombine() {
        assertDeallocated { AudioMenuViewModel() }
        assertDeallocated { SubtitleMenuViewModel() }
        assertDeallocated { PlaybackSpeedViewModel() }
        assertDeallocated { PlayerMenuViewModel() }
        assertDeallocated { MediaOptionsMenuViewModel() }
    }

    func testGestureResetCancelsEveryInFlightInteraction() {
        let clock = TestClock()
        let manager = GestureManager(clock: clock)
        manager.updateSurface(SurfaceGeometry(size: CGSize(width: 800, height: 400)))
        manager.currentTimeProvider = { 120 }
        manager.seekableRangeProvider = { 0 ... 600 }
        manager.isPlayingProvider = { true }

        var speeds: [Float] = []
        manager.speedProvider = { 1 }
        manager.onSetSpeed = { speeds.append($0) }

        manager.touchesBegan(at: CGPoint(x: 400, y: 200), touchCount: 1, source: .touch)
        clock.advance(by: 0.5)
        XCTAssertTrue(manager.speedHold.isEngaged)
        XCTAssertEqual(speeds.last, 2)

        manager.handleTap(at: CGPoint(x: 700, y: 200), in: CGSize(width: 800, height: 400))
        manager.coach.policy = .always
        manager.coach.playbackDidStart(
            capabilities: GestureCapabilities(),
            geometry: GestureGeometry(surface: SurfaceGeometry(size: CGSize(width: 800, height: 400)))
        )
        XCTAssertGreaterThan(clock.pendingCount, 0)

        manager.reset()

        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertFalse(manager.classifier.isActive)
        XCTAssertFalse(manager.scrub.isActive)
        XCTAssertFalse(manager.speedHold.isEngaged)
        XCTAssertNil(manager.scrollRailKind)
        XCTAssertNil(manager.scrollIdleToken)
        XCTAssertNil(manager.coach.stage)
        XCTAssertNil(manager.hudModel.hud)
        XCTAssertEqual(speeds.last, 1)
    }

    func testGestureResetCancelsAnActiveScrubWithoutSeeking() {
        let manager = GestureManager(clock: TestClock())
        manager.updateSurface(SurfaceGeometry(size: CGSize(width: 800, height: 400)))
        manager.currentTimeProvider = { 120 }
        manager.seekableRangeProvider = { 0 ... 600 }
        var seeks: [Double] = []
        manager.onSeek = { seeks.append($0) }

        manager.touchesBegan(at: CGPoint(x: 400, y: 200), touchCount: 1, source: .touch)
        manager.touchesMoved(to: CGPoint(x: 500, y: 200), touchCount: 1)
        XCTAssertTrue(manager.scrub.isActive)

        manager.reset()

        XCTAssertFalse(manager.scrub.isActive)
        XCTAssertTrue(seeks.isEmpty)
    }

    func testDisabledGestureLayerStillAllowsRecoveryTap() {
        let manager = GestureManager(clock: TestClock())
        manager.updateSurface(SurfaceGeometry(size: CGSize(width: 800, height: 400)))
        var configuration = GestureConfiguration()
        configuration.isEnabled = false
        manager.configuration = configuration
        var toggles = 0
        manager.onToggleControls = { toggles += 1 }

        manager.touchesBegan(at: CGPoint(x: 400, y: 200), touchCount: 1, source: .touch)
        manager.touchesEnded(at: CGPoint(x: 400, y: 200), touchCount: 1)

        XCTAssertEqual(toggles, 1)
        let capabilities = manager.currentCapabilities()
        XCTAssertFalse(capabilities.volume.isAvailable)
        XCTAssertFalse(capabilities.brightness.isAvailable)
        XCTAssertFalse(capabilities.scrub.isAvailable)
        XCTAssertFalse(capabilities.speedHold.isAvailable)
        XCTAssertFalse(capabilities.zoom.isAvailable)
    }

    func testRailLeadingAndTrailingFollowLayoutDirection() {
        let ltr = GestureGeometry(
            surface: SurfaceGeometry(
                size: CGSize(width: 800, height: 400),
                layoutDirection: .leftToRight
            )
        )
        let rtl = GestureGeometry(
            surface: SurfaceGeometry(
                size: CGSize(width: 800, height: 400),
                layoutDirection: .rightToLeft
            )
        )

        XCTAssertEqual(ltr.railSide(for: CGPoint(x: 100, y: 200)), .leading)
        XCTAssertEqual(rtl.railSide(for: CGPoint(x: 100, y: 200)), .trailing)
        XCTAssertLessThan(ltr.railFrame(.leading).midX, 400)
        XCTAssertGreaterThan(rtl.railFrame(.leading).midX, 400)
    }

    func testPinchAndAccessibilityZoomShareOneState() {
        let manager = GestureManager(clock: TestClock())
        var scales: [CGFloat] = []
        manager.onZoom = { scales.append($0) }

        manager.applyZoomPublic(fill: true)
        XCTAssertTrue(manager.isZoomFilled)

        manager.toggleZoom()
        XCTAssertFalse(manager.isZoomFilled)
        XCTAssertEqual(scales, [1.5, 0.5])
    }

    private func assertDeallocated<T: AnyObject>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ make: () -> T
    ) {
        weak var weakObject: T?
        autoreleasepool {
            var object: T? = make()
            weakObject = object
            object = nil
        }
        XCTAssertNil(weakObject, file: file, line: line)
    }
}
