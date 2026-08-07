import SwiftUI
import XCTest
@testable import PlayerKit

/// Behaviour of the YouTube-style double-tap skip.
///
/// The gesture is a small state machine with three jobs that pull against each
/// other: a single tap has to toggle the controls immediately, a second tap on
/// the same side has to take that toggle back and start skipping, and once a
/// session is open plain single taps have to keep skipping instead of toggling.
/// Each of those is pinned down here.
@MainActor
final class DoubleTapSeekGestureTests: XCTestCase {

    private let size = CGSize(width: 400, height: 200)
    private var leftSide: CGPoint { CGPoint(x: 40, y: 100) }
    private var rightSide: CGPoint { CGPoint(x: 360, y: 100) }
    private var center: CGPoint { CGPoint(x: 200, y: 100) }

    /// A manager wired to a playhead that follows the seeks it is told to make,
    /// so re-anchoring is observable.
    private func makeManager(
        startingAt playhead: Double = 100,
        range: ClosedRange<Double>? = 0 ... 600
    ) -> (GestureManager, Probe) {
        let probe = Probe(playhead: playhead)
        let manager = GestureManager()
        manager.currentTimeProvider = { probe.playhead }
        manager.seekableRangeProvider = { range }
        manager.onSeek = { target in
            probe.seekTargets.append(target)
            probe.playhead = target
        }
        manager.onToggleControls = { probe.toggleCount += 1 }
        manager.onControlsVisibilityChange = { probe.visibilityChanges.append($0) }
        manager.onSeekSessionChange = { probe.sessionChanges.append($0) }
        return (manager, probe)
    }

    private final class Probe {
        var playhead: Double
        var seekTargets: [Double] = []
        var toggleCount = 0
        var visibilityChanges: [Bool] = []
        var sessionChanges: [Bool] = []

        init(playhead: Double) {
            self.playhead = playhead
        }
    }

    // MARK: - Single tap

    /// The toggle is no longer held back for the length of the double-tap
    /// window: one tap shows or hides the controls straight away.
    func testSingleTapTogglesControlsImmediately() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)

        XCTAssertEqual(probe.toggleCount, 1)
        XCTAssertTrue(probe.seekTargets.isEmpty)
        XCTAssertNil(manager.seekOverlay)
    }

    // MARK: - Double tap

    func testDoubleTapSkipsAndTakesBackTheControlsToggle() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)

        XCTAssertEqual(probe.seekTargets, [110])
        // The first tap toggled; the second one skipped instead of toggling
        // again, and put the controls away.
        XCTAssertEqual(probe.toggleCount, 1)
        XCTAssertEqual(probe.visibilityChanges, [false])
    }

    /// The point of the session: after the opening double tap, *single* taps
    /// keep stacking skips, which is what makes "tap tap tap tap" reach +40s.
    func testFurtherSingleTapsKeepAccumulatingWithinTheSession() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)

        XCTAssertEqual(probe.seekTargets, [110, 120, 130])
        XCTAssertEqual(manager.seekOverlay?.seconds, 30)
        // None of the continuation taps touched the controls.
        XCTAssertEqual(probe.toggleCount, 1)
    }

    /// Turning around counts from wherever the playhead is now, so a back-tap
    /// after "forward 20" reads 10 rather than continuing the old total.
    func testReversingRestartsTheCountFromTheCurrentPosition() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: leftSide, in: size)

        XCTAssertEqual(probe.seekTargets, [110, 120, 110])
        XCTAssertEqual(manager.seekOverlay?.direction, .backward)
        XCTAssertEqual(manager.seekOverlay?.seconds, 10)
    }

    /// Both taps have to land on the same side. Left-then-right is two single
    /// taps, not a skip.
    func testTapsOnOppositeSidesDoNotSkip() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: leftSide, in: size)
        manager.handleTap(at: rightSide, in: size)

        XCTAssertTrue(probe.seekTargets.isEmpty)
        XCTAssertEqual(probe.toggleCount, 2)
    }

    /// The middle band is deliberately inert, so a quick double tap aimed at
    /// the controls does not skip by accident.
    func testDoubleTapInTheCentreDeadZoneOnlyTogglesControls() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: center, in: size)
        manager.handleTap(at: center, in: size)

        XCTAssertTrue(probe.seekTargets.isEmpty)
        XCTAssertEqual(probe.toggleCount, 2)
        XCTAssertNil(manager.seekOverlay)
    }

    /// A dead-zone tap during a session ends it rather than being swallowed.
    func testCentreTapDuringASessionEndsItAndTogglesControls() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: center, in: size)

        XCTAssertEqual(probe.seekTargets, [110])
        XCTAssertNil(manager.seekOverlay)
        XCTAssertEqual(probe.toggleCount, 2)
    }

    // MARK: - Lock

    /// Locked, a double tap must not skip — and must not hide the controls
    /// either, which is how the unlock button stays reachable.
    func testDoubleTapDoesNothingWhileLocked() {
        let (manager, probe) = makeManager()
        manager.isLockedProvider = { true }

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)

        XCTAssertTrue(probe.seekTargets.isEmpty)
        XCTAssertTrue(probe.visibilityChanges.isEmpty)
        XCTAssertNil(manager.seekOverlay)
        XCTAssertEqual(probe.toggleCount, 2)
    }

    // MARK: - Overlay state

    func testOverlayCarriesTheSideTotalAndTapOrigin() {
        let (manager, _) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        let first = manager.seekOverlay

        XCTAssertEqual(first?.direction, .forward)
        XCTAssertEqual(first?.seconds, 10)
        // Stored as a fraction of the surface, not as raw points: the overlay
        // outlives a rotation, and a point captured against the pre-rotation
        // size would put the ripple off-screen after one.
        XCTAssertEqual(first?.unitOrigin.x ?? 0, rightSide.x / size.width, accuracy: 0.0001)
        XCTAssertEqual(first?.unitOrigin.y ?? 0, rightSide.y / size.height, accuracy: 0.0001)
        XCTAssertTrue(manager.isDoubleTapSeeking)

        manager.handleTap(at: rightSide, in: size)

        XCTAssertEqual(manager.seekOverlay?.seconds, 20)
        // A fresh id per tap is what replays the ripple from the new fingertip.
        XCTAssertNotEqual(manager.seekOverlay?.tapID, first?.tapID)
    }

    /// A skip that could not happen must not be advertised: with no seekable
    /// range there is no seek *and* no overlay.
    func testNoOverlayWhenThereIsNothingToSeekWithin() {
        let (manager, probe) = makeManager(range: nil)

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)

        XCTAssertTrue(probe.seekTargets.isEmpty)
        XCTAssertNil(manager.seekOverlay)
        XCTAssertFalse(manager.isDoubleTapSeeking)
    }

    // MARK: - Session transitions

    /// The controls mirror this flag, so it has to report the two edges of a
    /// session and stay quiet for the taps in between — that is the whole point
    /// of it existing separately from the per-tap overlay.
    func testSessionChangeReportsOnlyTheOpenAndCloseEdges() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        XCTAssertEqual(probe.sessionChanges, [true])

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        XCTAssertEqual(manager.seekOverlay?.seconds, 30)
        // Three more taps, three more overlay updates, no further edges.
        XCTAssertEqual(probe.sessionChanges, [true])

        manager.reset()
        XCTAssertEqual(probe.sessionChanges, [true, false])
    }

    /// Reversing stays inside one session — the overlay swaps sides but the
    /// controls must not see it close and reopen.
    func testReversingDoesNotReopenTheSession() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: leftSide, in: size)

        XCTAssertEqual(probe.sessionChanges, [true])
    }

    /// Ending a session that never opened must not publish to anyone.
    func testEndingAnUnopenedSessionIsSilent() {
        let (manager, probe) = makeManager()

        manager.reset()
        manager.handleTap(at: center, in: size)
        manager.handleTap(at: center, in: size)
        manager.reset()

        XCTAssertTrue(probe.sessionChanges.isEmpty)
    }

    func testResetClearsAnOpenSession() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        manager.reset()

        XCTAssertNil(manager.seekOverlay)
        XCTAssertFalse(manager.isDoubleTapSeeking)

        // Back to square one: the next tap is an ordinary single tap.
        manager.handleTap(at: rightSide, in: size)
        XCTAssertEqual(probe.toggleCount, 2)
        XCTAssertEqual(probe.seekTargets.count, 1)
    }

    // MARK: - Session timeout

    /// The session has to close on its own, or every later tap would keep
    /// skipping and the controls could never be summoned again.
    func testSessionClosesAfterTheTimeoutSoTapsToggleAgain() {
        let (manager, probe) = makeManager()

        manager.handleTap(at: rightSide, in: size)
        manager.handleTap(at: rightSide, in: size)
        XCTAssertNotNil(manager.seekOverlay)

        let elapsed = expectation(description: "seek session timed out")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 3)

        XCTAssertNil(manager.seekOverlay)

        manager.handleTap(at: rightSide, in: size)
        XCTAssertEqual(probe.seekTargets, [110])
        XCTAssertEqual(probe.toggleCount, 2)
    }

    // MARK: - Discrete skips (buttons, keyboard, rotor)

    /// The location-free entry points do a plain seek: chrome up, no session,
    /// no overlay, no toggle. This pins the routing itself — the machine-level
    /// tests cannot notice skipForward being rerouted back through the
    /// session path.
    func testSkipForwardIsAPlainSeekThatWakesTheChrome() {
        let (manager, probe) = makeManager()

        manager.skipForward()

        XCTAssertEqual(probe.seekTargets, [110])
        XCTAssertNil(manager.seekOverlay)
        XCTAssertFalse(manager.isDoubleTapSeeking)
        XCTAssertEqual(probe.visibilityChanges, [true])
        XCTAssertTrue(probe.sessionChanges.isEmpty)
        XCTAssertEqual(probe.toggleCount, 0)
    }

    func testSkipBackwardIsAPlainSeek() {
        let (manager, probe) = makeManager()

        manager.skipBackward()

        XCTAssertEqual(probe.seekTargets, [90])
        XCTAssertNil(manager.seekOverlay)
    }

    /// A committed scrub is a seek the tap machine did not issue: a button
    /// press right after it must continue from the scrub's landing point, not
    /// yank the playhead back toward the press before the scrub.
    func testScrubCommitSupersedesTheDiscreteAnchor() {
        let (manager, probe) = makeManager()

        manager.skipForward()                           // 110
        manager.emit(.scrubEnded(committedTarget: 300)) // The scrub commits…
        manager.emit(.seek(to: 300))                    // …and issues its seek.
        manager.skipForward()

        XCTAssertEqual(probe.seekTargets, [110, 300, 310])
    }

    // MARK: - Overlay geometry

    /// The seek pulse is drawn with no clip at all, which is only safe because
    /// nothing it emits can reach the midline or the screen edge. The disc is
    /// pinned at quarter-width and the ring grows concentrically from it, so
    /// the contract is symmetric: centre ± reach stays inside the tapped half.
    /// Checked across the aspect ratios a player actually gets, from a portrait
    /// phone to a wide desktop window.
    func testSeekPulseCannotLeaveTheTappedHalf() {
        let widths: [CGFloat] = [320, 390, 430, 744, 852, 1024, 1366, 1920, 3840]

        for width in widths {
            for isForward in [false, true] {
                let center = DoubleTapSeekOverlayView.pulseCenterX(
                    forWidth: width,
                    isForward: isForward
                )
                let reach = DoubleTapSeekOverlayView.pulseReach(forWidth: width)
                let half = isForward
                    ? (width / 2)...width
                    : 0...(width / 2)

                XCTAssertTrue(
                    half.contains(center - reach) && half.contains(center + reach),
                    "A pulse at width \(width) spans \(center - reach)...\(center + reach), outside \(half)"
                )
            }
        }
    }

    /// The pulse still has to be big enough to read as feedback, and the ring
    /// must always clear the disc it is emitted from.
    func testSeekPulseStaysVisibleOnSmallScreens() {
        for width: CGFloat in [320, 390, 1120] {
            XCTAssertGreaterThan(
                DoubleTapSeekOverlayView.pulseReach(forWidth: width),
                DoubleTapSeekOverlayView.discDiameter / 2,
                "The ring at width \(width) never escapes the disc"
            )
        }
    }
}
