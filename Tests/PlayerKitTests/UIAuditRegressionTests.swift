import CoreGraphics
import XCTest
@testable import PlayerKit

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

    func testPlayerViewLoadIdentityFollowsEveryInputAndIsStableForNaN() {
        let url = URL(string: "https://example.com/video.m3u8")!
        let first = PlayerItem(title: "One", url: url, lastPosition: .nan, episodeIndex: 1)
        let renamed = PlayerItem(title: "Two", url: url, lastPosition: .nan, episodeIndex: 1)

        let firstIdentity = PlayerView.LoadMode.single(first).identity
        XCTAssertEqual(firstIdentity, PlayerView.LoadMode.single(first).identity)
        XCTAssertNotEqual(firstIdentity, PlayerView.LoadMode.single(renamed).identity)
        XCTAssertNotEqual(
            PlayerView.LoadMode.episodes([first], 0).identity,
            PlayerView.LoadMode.episodes([first], 1).identity
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
