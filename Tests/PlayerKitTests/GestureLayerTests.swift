import CoreGraphics
import XCTest
@testable import PlayerKit

// MARK: - Fakes

/// A level control that records every write, so the quantum and frame gates are
/// observable without a device.
private final class FakeLevelControl: OutputLevelControlling {
    var availability: GestureAvailability = .available
    var isSystemWide: Bool = false
    var writeQuantum: Double = 1.0 / 16.0
    var onExternalChange: ((Double) -> Void)?

    private(set) var writes: [Double] = []
    private(set) var refreshCount = 0
    var level: Double = 0.5

    func readLevel() -> Double { level }

    func setLevel(_ value: Double) {
        level = value
        writes.append(value)
    }

    func refreshBaseline() { refreshCount += 1 }
    func relinquish(force: Bool) {}
}

// MARK: - Tap machine

/// The tap machine's correctness, exercised against a playhead that behaves like
/// a real backend rather than an idealised one.
@MainActor
final class TapSeekMachineTests: XCTestCase {

    /// A playhead that does **not** move when a seek is issued.
    ///
    /// This is the whole point. `AVPlayer.currentTime()` only advances once the
    /// seek actually lands, and `VLCPlayerWrapper.seek` is explicitly
    /// asynchronous. The previous test probe applied seeks synchronously, which
    /// modelled the one behaviour no real player has — and that is why the
    /// reversal bug survived a green suite.
    private final class LaggingProbe {
        var playhead: Double
        var seeks: [Double] = []
        var intents: [GestureIntent] = []

        init(playhead: Double) { self.playhead = playhead }
    }

    private func makeMachine(
        playhead: Double = 100,
        range: ClosedRange<Double>? = 0 ... 600,
        controlsVisible: Bool = true
    ) -> (TapSeekMachine, LaggingProbe, TestClock) {
        let clock = TestClock()
        let probe = LaggingProbe(playhead: playhead)
        let machine = TapSeekMachine(clock: clock)
        machine.currentTimeProvider = { probe.playhead }
        machine.seekableRangeProvider = { range }
        machine.areControlsVisibleProvider = { controlsVisible }
        machine.emit = { intent in
            probe.intents.append(intent)
            if case .seek(let target) = intent { probe.seeks.append(target) }
        }
        return (machine, probe, clock)
    }

    private let leftUnit = CGPoint(x: 0.1, y: 0.5)
    private let rightUnit = CGPoint(x: 0.9, y: 0.5)

    /// Reversing must re-base on the last target **issued**, not on where the
    /// playhead currently reads.
    ///
    /// Three fast forward taps from 100 issue 110/120/130. With the seeks still
    /// in flight the playhead still reads 100, so the old code re-anchored there
    /// and sent the user to 90 while the overlay said "10 seconds" — a 40-second
    /// regression labelled as ten.
    func testReversalAnchorsToTheLastIssuedTargetNotTheLaggingPlayhead() {
        let (machine, probe, _) = makeMachine()

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        XCTAssertEqual(probe.seeks, [110, 120, 130])

        // The playhead has not moved at all — every seek is still in flight.
        XCTAssertEqual(probe.playhead, 100)

        machine.handleTap(unitOrigin: leftUnit, zone: .backward)

        XCTAssertEqual(probe.seeks.last, 120, "A back tap after +30 must land 10s back from 130, not from the stale playhead")
        XCTAssertEqual(machine.overlay?.seconds, 10)
        XCTAssertEqual(machine.overlay?.direction, .backward)
    }

    /// A double tap on a stream with no seekable window must not delete the
    /// interface. The old code hid the chrome first and discovered there was
    /// nothing to seek within afterwards, and nothing put it back.
    func testNoSeekableRangeLeavesTheControlsAlone() {
        let (machine, probe, _) = makeMachine(range: nil)

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)

        XCTAssertTrue(probe.seeks.isEmpty)
        XCTAssertNil(machine.overlay)
        XCTAssertFalse(
            probe.intents.contains(.setControlsVisible(false)),
            "The chrome must not be hidden for a skip that cannot happen"
        )
    }

    /// A skip that is already hard against the end of the window must not keep
    /// advertising ten more seconds it did not deliver.
    func testSkipClampedToZeroRollsTheReadoutBack() {
        let (machine, probe, _) = makeMachine(playhead: 595, range: 0 ... 600)

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        XCTAssertEqual(probe.seeks, [600])
        XCTAssertEqual(machine.overlay?.seconds, 10)

        // Already at the end: the next tap achieves nothing.
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)

        XCTAssertEqual(probe.seeks, [600], "No second seek — there was nowhere to go")
        XCTAssertEqual(machine.overlay?.seconds, 10, "The readout must not climb past a skip that did not happen")
    }

    /// With the chrome hidden, the first tap of a possible skip holds its *show*
    /// back, so a double tap does not wash the whole interface in and out behind
    /// the overlay.
    func testFirstTapDefersTheShowWhileControlsAreHidden() {
        let (machine, probe, clock) = makeMachine(controlsVisible: false)

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)

        XCTAssertEqual(probe.intents.first, .toggleControls(.deferredUntilDoubleTapWindowCloses))
        XCTAssertFalse(probe.intents.contains(.toggleControls(.immediate)))

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        clock.advance(by: 1.0)

        XCTAssertFalse(
            probe.intents.contains(.toggleControls(.immediate)),
            "The deferred show must be taken back by the second tap, never performed"
        )
        XCTAssertEqual(probe.seeks, [110])
    }

    /// A deferred show that is never followed by a second tap still has to happen.
    func testDeferredShowFiresWhenNoSecondTapArrives() {
        let (machine, probe, clock) = makeMachine(controlsVisible: false)

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        clock.advance(by: 0.3)

        XCTAssertTrue(probe.intents.contains(.toggleControls(.immediate)))
    }

    /// With the chrome already up, a tap hides it immediately — no user should
    /// wait 0.28s to dismiss something.
    func testVisibleControlsHideImmediately() {
        let (machine, probe, _) = makeMachine(controlsVisible: true)

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)

        XCTAssertEqual(probe.intents.first, .toggleControls(.immediate))
    }

    /// The button/rotor/keyboard path is a plain seek: it must not open the
    /// double-tap session, draw the accumulation overlay, or hide the chrome.
    /// It wakes the chrome instead, the way any control press does.
    func testLocationFreeSkipSeeksWithoutOpeningASession() {
        let (machine, probe, _) = makeMachine()

        machine.skip(.forward)

        XCTAssertEqual(probe.seeks, [110])
        XCTAssertNil(machine.overlay)
        XCTAssertFalse(machine.isSeeking)
        XCTAssertFalse(probe.intents.contains(.setControlsVisible(false)))
        XCTAssertFalse(probe.intents.contains(.toggleControls(.immediate)))
        XCTAssertTrue(probe.intents.contains(.setControlsVisible(true)))
    }

    /// Rapid presses still anchor on the last *issued* target: with every seek
    /// in flight the playhead reads stale, and re-reading it would make three
    /// fast +10s land +10.
    func testRapidDiscreteSkipsAnchorOnTheLastIssuedTarget() {
        let (machine, probe, _) = makeMachine()

        machine.skip(.forward)
        machine.skip(.forward)
        machine.skip(.forward)

        XCTAssertEqual(probe.playhead, 100, "Every seek is still in flight")
        XCTAssertEqual(probe.seeks, [110, 120, 130])
        XCTAssertNil(machine.overlay)
    }

    /// Once the anchor window closes, the next press re-reads the playhead —
    /// an anchor that never expired would drift away from a paused stream.
    func testDiscreteAnchorExpiresAfterTheSessionTimeout() {
        let (machine, probe, clock) = makeMachine()

        machine.skip(.forward)
        probe.playhead = 110 // The seek landed.
        clock.advance(by: 1.0)
        machine.skip(.forward)

        XCTAssertEqual(probe.seeks, [110, 120])
    }

    /// A press while a fingertip session is open takes the session over: the
    /// overlay comes down and the skip continues from where the session was
    /// already headed, never from the lagging playhead behind it.
    func testDiscreteSkipDuringASessionClosesItAndContinuesFromItsTarget() {
        let (machine, probe, _) = makeMachine()

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        XCTAssertEqual(probe.seeks, [110])
        XCTAssertNotNil(machine.overlay)

        machine.skip(.forward)

        XCTAssertEqual(probe.seeks, [110, 120])
        XCTAssertNil(machine.overlay)
        XCTAssertFalse(machine.isSeeking)
    }

    /// The reverse handover: a double tap right after a press anchors on the
    /// press's target, so the two mechanisms cannot fight over a stale
    /// playhead.
    func testDoubleTapAfterDiscreteSkipAnchorsOnItsTarget() {
        let (machine, probe, _) = makeMachine()

        machine.skip(.forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)

        XCTAssertEqual(probe.seeks, [110, 120])
        XCTAssertEqual(machine.overlay?.seconds, 10)
    }

    /// Hard against the end of the window a press does nothing at all — no
    /// seek, no chrome wake, and a zero return so the caller stays quiet.
    func testDiscreteSkipAtTheEdgeIsSilent() {
        let (machine, probe, _) = makeMachine(playhead: 600, range: 0 ... 600)

        let achieved = machine.skip(.forward)

        XCTAssertEqual(achieved, 0)
        XCTAssertTrue(probe.seeks.isEmpty)
        XCTAssertFalse(probe.intents.contains(.setControlsVisible(true)))
    }

    /// A backward press is one interval back, and the DVR case matters: the
    /// clamp must land on the window's start, not on zero, or one back-press
    /// on a live stream throws the playhead to the top of the DVR window.
    func testDiscreteBackwardSkipClampsToTheWindowStart() {
        let (machine, probe, _) = makeMachine(playhead: 3605, range: 3600 ... 7200)

        let achieved = machine.skip(.backward)

        XCTAssertEqual(probe.seeks, [3600])
        XCTAssertEqual(achieved, 5)
    }

    func testDiscreteBackwardSkipSeeksOneIntervalBack() {
        let (machine, probe, _) = makeMachine()

        XCTAssertEqual(machine.skip(.backward), 10)
        XCTAssertEqual(probe.seeks, [90])
    }

    /// A partially clamped press reports the movement it actually bought —
    /// the number VoiceOver announces.
    func testPartiallyClampedDiscreteSkipReturnsTheAchievedMovement() {
        let (machine, probe, _) = makeMachine(playhead: 595, range: 0 ... 600)

        XCTAssertEqual(machine.skip(.forward), 5)
        XCTAssertEqual(probe.seeks, [600])
    }

    /// A seek the machine did not issue — slider, remote, host — supersedes
    /// the discrete anchor: the next press continues from the playhead, not
    /// from where a previous press was headed.
    func testExternalSeekDropsTheDiscreteAnchor() {
        let (machine, probe, _) = makeMachine()

        machine.skip(.forward)
        machine.noteExternalSeek() // The slider moved the playhead…
        probe.playhead = 300       // …and that seek landed.
        machine.skip(.forward)

        XCTAssertEqual(probe.seeks, [110, 310])
    }

    /// The same supersession closes an open fingertip session: its committed
    /// target is just as stale, and the overlay must not keep counting on top
    /// of a playhead someone else moved.
    func testExternalSeekEndsAnOpenSession() {
        let (machine, probe, _) = makeMachine()

        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        machine.handleTap(unitOrigin: rightUnit, zone: .forward)
        XCTAssertNotNil(machine.overlay)
        XCTAssertEqual(probe.seeks, [110])

        machine.noteExternalSeek()

        XCTAssertNil(machine.overlay)
        XCTAssertFalse(machine.isSeeking)
    }

    /// The media-change path: reset() must drop the anchor, or a press in the
    /// next item would seek off the previous item's playhead.
    func testResetDropsTheDiscreteAnchor() {
        let (machine, probe, _) = makeMachine()

        machine.skip(.forward)
        machine.reset()
        machine.skip(.forward)

        XCTAssertEqual(
            probe.seeks,
            [110, 110],
            "After reset the press must re-read the playhead, not the old target"
        )
    }

    func testLockedSkipIsReportedRatherThanSwallowed() {
        let (machine, probe, _) = makeMachine()
        machine.isLockedProvider = { true }

        machine.skip(.forward)

        XCTAssertTrue(probe.intents.contains(.blocked(.skip)))
        XCTAssertTrue(probe.seeks.isEmpty)
    }
}

// MARK: - Classifier

@MainActor
final class TouchClassifierTests: XCTestCase {

    private func makeClassifier() -> TouchClassifier {
        let classifier = TouchClassifier()
        classifier.begin(
            at: CGPoint(x: 200, y: 200),
            touchCount: 1,
            now: 0,
            tuning: TouchClassifier.Tuning(),
            source: .touch
        )
        return classifier
    }

    private func context(
        rail: GestureAvailability = .available,
        scrub: Bool = true,
        side: RailSide? = .trailing,
        eligible: Bool = true
    ) -> ClassificationContext {
        ClassificationContext(
            railAvailability: { _ in rail },
            isScrubAvailable: scrub,
            startSide: side,
            isPanEligible: eligible
        )
    }

    func testTravelUnderSlopStaysUndecided() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 4, height: 4), touchCount: 1, now: 0.05, context: context())
        XCTAssertEqual(classifier.outcome, .undecided)
    }

    func testDominantVerticalClaimsTheRail() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 2, height: 40), touchCount: 1, now: 0.1, context: context())
        XCTAssertEqual(classifier.outcome, .verticalRail(.trailing))
    }

    func testDominantHorizontalClaimsTheScrub() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 40, height: 2), touchCount: 1, now: 0.1, context: context())
        XCTAssertEqual(classifier.outcome, .horizontalScrub)
    }

    /// The band either side of the diagonal is deliberately left unclaimed
    /// rather than arbitrarily assigned, so a genuinely ambiguous drag keeps
    /// sampling instead of guessing wrong and locking in.
    func testDiagonalStaysUnclaimedAndKeepsSampling() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 30, height: 30), touchCount: 1, now: 0.1, context: context())
        XCTAssertEqual(classifier.outcome, .undecided)

        classifier.update(translation: CGSize(width: 30, height: 90), touchCount: 1, now: 0.2, context: context())
        XCTAssertEqual(classifier.outcome, .verticalRail(.trailing))
    }

    /// Once resolved, a touch is never re-classified: a finger that commits to
    /// volume and then wanders sideways keeps adjusting volume.
    func testResolvedOutcomeIsNeverReclassified() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 0, height: 40), touchCount: 1, now: 0.1, context: context())
        classifier.update(translation: CGSize(width: 200, height: 40), touchCount: 1, now: 0.2, context: context())
        XCTAssertEqual(classifier.outcome, .verticalRail(.trailing))
    }

    /// The engagement translation is what later gets subtracted, and it is what
    /// removes the visible lurch the old code produced on engagement.
    func testEngagementTranslationIsCapturedAtTheLockPoint() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 0, height: 40), touchCount: 1, now: 0.1, context: context())
        XCTAssertEqual(classifier.engagementTranslation.height, 40)
    }

    /// A capability the platform lacks must not swallow the touch.
    func testUnavailableRailFallsThroughRatherThanVanishing() {
        let classifier = makeClassifier()
        classifier.update(
            translation: CGSize(width: 0, height: 40),
            touchCount: 1,
            now: 0.1,
            context: context(rail: .unavailable(.notSupportedOnPlatform))
        )
        XCTAssertEqual(classifier.outcome, .inert(.notSupportedOnPlatform))
    }

    /// A pan that begins on a system edge is never claimed, so the touch resolves
    /// as an ordinary tap instead of half-driving a rail the OS is about to steal.
    func testPanBegunOutsideTheEligibleRectIsNotClaimed() {
        let classifier = makeClassifier()
        classifier.update(
            translation: CGSize(width: 0, height: 60),
            touchCount: 1,
            now: 0.1,
            context: context(eligible: false)
        )
        XCTAssertEqual(classifier.outcome, .undecided)
    }

    func testShortUnresolvedLiftIsStillATap() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 12, height: 12), touchCount: 1, now: 0.05, context: context())
        XCTAssertEqual(classifier.finish(cancelled: false), .tap)
    }

    /// UIKit can deliver an end and a cancel for the same sequence, so the
    /// ordering between the two has to stop mattering.
    func testFinishIsIdempotent() {
        let classifier = makeClassifier()
        XCTAssertNotNil(classifier.finish(cancelled: false))
        XCTAssertNil(classifier.finish(cancelled: true))
    }

    /// A hold means the touch can never also be a tap, which is what stops a
    /// released long-press from toggling the controls on the way out.
    func testPromotedHoldCannotAlsoBecomeATap() {
        let classifier = makeClassifier()
        XCTAssertTrue(classifier.promoteToHold())
        XCTAssertEqual(classifier.finish(cancelled: false), .speedHold)
    }

    func testArmingRequiresAStillFinger() {
        let classifier = makeClassifier()
        classifier.update(translation: CGSize(width: 40, height: 0), touchCount: 1, now: 0.1, context: context())
        XCTAssertFalse(classifier.promoteToArmed(), "A finger already scrubbing must not arm a rail")
    }
}

// MARK: - Geometry

@MainActor
final class GestureGeometryTests: XCTestCase {

    private func geometry(
        size: CGSize = CGSize(width: 852, height: 393),
        capabilities: GestureCapabilities = GestureCapabilities()
    ) -> GestureGeometry {
        GestureGeometry(
            surface: SurfaceGeometry(size: size),
            capabilities: capabilities,
            railMapping: .brightnessLeading
        )
    }

    /// The invariant that makes one geometry model safe for both partitions: a
    /// seek tap zone is strictly inside its own rail half, so no x is ever
    /// "backward" to a tap and "trailing" to a swipe. The old code split taps
    /// 0.4/0.2/0.4 and swipes 0.33/0.34/0.33, and disagreed between them.
    func testTapZonesNestInsideRailHalves() {
        let geometry = self.geometry()
        let width = geometry.size.width

        for ratio in stride(from: 0.01, through: 0.99, by: 0.01) {
            let point = CGPoint(x: width * CGFloat(ratio), y: 200)
            let zone = geometry.tapZone(for: point)
            let side = geometry.railSide(for: point)
            switch zone {
            case .backward: XCTAssertEqual(side, .leading, "x ratio \(ratio)")
            case .forward: XCTAssertEqual(side, .trailing, "x ratio \(ratio)")
            case .center: break
            }
        }
    }

    /// The rail covers the full height, not the middle third. The old partition
    /// accepted a swipe in roughly a fifth of the surface, which is the single
    /// biggest reason the gesture read as broken.
    func testRailsCoverTheFullUsableHeight() {
        let geometry = self.geometry()
        let top = CGPoint(x: 700, y: geometry.activeRect.minY + 1)
        let bottom = CGPoint(x: 700, y: geometry.activeRect.maxY - 1)

        XCTAssertEqual(geometry.railSide(for: top), .trailing)
        XCTAssertEqual(geometry.railSide(for: bottom), .trailing)
        XCTAssertTrue(geometry.isPanEligible(top))
        XCTAssertTrue(geometry.isPanEligible(bottom))
    }

    func testFullRangeTravelStaysInsideItsBounds() {
        for height in [180.0, 393.0, 834.0, 1366.0] {
            let geometry = self.geometry(size: CGSize(width: 1024, height: height))
            XCTAssertGreaterThanOrEqual(geometry.fullRangeTravel, 160)
            XCTAssertLessThanOrEqual(geometry.fullRangeTravel, 260)
        }
    }

    /// Where brightness cannot be driven, both halves drive volume rather than
    /// leaving half the picture inert. This is the macOS story.
    func testBothHalvesDriveVolumeWhenBrightnessIsUnavailable() {
        var capabilities = GestureCapabilities()
        capabilities.brightness = .unavailable(.notSupportedOnPlatform)
        let geometry = self.geometry(capabilities: capabilities)

        XCTAssertEqual(geometry.kind(forSide: .leading), .volume)
        XCTAssertEqual(geometry.kind(forSide: .trailing), .volume)
    }

    func testUnusableSurfaceDegradesSafely() {
        let geometry = self.geometry(size: .zero)
        XCTAssertFalse(geometry.isUsable)
        XCTAssertEqual(geometry.tapZone(for: .zero), .center)
        XCTAssertNil(geometry.railSide(for: .zero))
        XCTAssertFalse(geometry.isPanEligible(.zero))
    }

    /// A unit origin survives rotation; a raw point captured against the
    /// pre-rotation size does not.
    func testUnitPointRoundTripsAcrossASizeChange() {
        let geometry = self.geometry()
        let unit = geometry.unitPoint(CGPoint(x: 639, y: 196.5))
        let rotated = geometry.point(fromUnit: unit, in: CGSize(width: 393, height: 852))

        XCTAssertEqual(rotated.x, 393 * 0.75, accuracy: 0.5)
        XCTAssertEqual(rotated.y, 852 * 0.5, accuracy: 0.5)
    }
}

// MARK: - Rail

@MainActor
final class VerticalRailControllerTests: XCTestCase {

    /// Writes are quantised to the control's own resolution and gated to one per
    /// display frame — a 120Hz drag must not cross a process boundary 120 times
    /// a second.
    func testWritesAreQuantisedAndFrameGated() {
        let control = FakeLevelControl()
        let rail = VerticalRailController()
        rail.begin(kind: .volume, control: control, at: CGPoint(x: 700, y: 200), now: 0)

        // Many tiny movements inside one frame and one quantum.
        for step in 1 ... 20 {
            rail.update(
                dy: CGFloat(-step) * 0.1,
                at: CGPoint(x: 700, y: 200 - CGFloat(step) * 0.1),
                now: 0,
                travel: 200,
                control: control,
                feedback: nil,
                hapticsEnabled: false
            )
        }

        XCTAssertLessThanOrEqual(control.writes.count, 1)
    }

    /// The baseline is captured at touch down, so anything that changed the
    /// level between two swipes cannot make the next swipe's first frame jump.
    func testBaselineIsReadAtBeginNotAtEnd() {
        let control = FakeLevelControl()
        control.level = 0.25
        let rail = VerticalRailController()

        rail.begin(kind: .volume, control: control, at: .zero, now: 0)
        XCTAssertEqual(control.refreshCount, 1)

        let sample = rail.update(
            dy: -100,
            at: CGPoint(x: 0, y: -100),
            now: 1,
            travel: 200,
            control: control,
            feedback: nil,
            hapticsEnabled: false
        )
        // 0.25 baseline + 100/200 of travel.
        XCTAssertEqual(sample.unit, 0.75, accuracy: 0.0001)
    }

    func testValueClampsAndReportsPinning() {
        let control = FakeLevelControl()
        control.level = 0.9
        let rail = VerticalRailController()
        rail.begin(kind: .volume, control: control, at: .zero, now: 0)

        let sample = rail.update(
            dy: -400,
            at: CGPoint(x: 0, y: -400),
            now: 1,
            travel: 200,
            control: control,
            feedback: nil,
            hapticsEnabled: false
        )

        XCTAssertEqual(sample.unit, 1)
        XCTAssertTrue(sample.isPinned)
    }

    /// The end stop thuds once, not on every further event pushing into it.
    func testEndStopHapticLatches() {
        let control = FakeLevelControl()
        control.level = 0.9
        let feedback = RecordingFeedback()
        let rail = VerticalRailController()
        rail.begin(kind: .volume, control: control, at: .zero, now: 0)

        for step in 1 ... 5 {
            rail.update(
                dy: -400 - CGFloat(step),
                at: CGPoint(x: 0, y: -400),
                now: Double(step) * 0.02,
                travel: 200,
                control: control,
                feedback: feedback,
                hapticsEnabled: true
            )
        }

        XCTAssertEqual(feedback.impacts.filter { $0 == .rigid }.count, 1)
    }

    /// Lifting between two gated frames must not leave the control a step behind
    /// the rail the user was looking at.
    func testEndFlushesTheFinalValue() {
        let control = FakeLevelControl()
        let rail = VerticalRailController()
        rail.begin(kind: .volume, control: control, at: .zero, now: 0)
        rail.update(dy: -37, at: .zero, now: 0, travel: 200, control: control, feedback: nil, hapticsEnabled: false)
        rail.end(control: control)

        XCTAssertEqual(control.level, rail.currentValue, accuracy: 0.0001)
    }
}

// MARK: - Scrub

@MainActor
final class ScrubControllerTests: XCTestCase {

    func testOffsetIsIntegratedSoATierChangeOnlyRatesLaterTravel() {
        let scrub = ScrubController()
        scrub.begin(from: 100, range: 0 ... 1000, secondsPerPoint: 1, engagementTranslation: .zero)

        // 100pt at full rate.
        var sample = scrub.update(translation: CGSize(width: 100, height: 0), feedback: nil, hapticsEnabled: false)
        XCTAssertEqual(sample.target, 200, accuracy: 0.001)

        // Drop into quarter rate and travel another 100pt.
        sample = scrub.update(translation: CGSize(width: 200, height: 120), feedback: nil, hapticsEnabled: false)
        XCTAssertEqual(sample.tier, .quarter)
        XCTAssertEqual(sample.target, 225, accuracy: 0.001, "Only the travel after the tier change is re-rated")
    }

    func testTargetClampsIntoTheSeekableRange() {
        let scrub = ScrubController()
        scrub.begin(from: 990, range: 0 ... 1000, secondsPerPoint: 1, engagementTranslation: .zero)
        let sample = scrub.update(translation: CGSize(width: 500, height: 0), feedback: nil, hapticsEnabled: false)
        XCTAssertEqual(sample.target, 1000)
    }

    /// Pushing past the end and dragging back must not have to unwind dead
    /// travel first.
    func testPushingPastTheEndDoesNotAccumulateDeadTravel() {
        let scrub = ScrubController()
        scrub.begin(from: 990, range: 0 ... 1000, secondsPerPoint: 1, engagementTranslation: .zero)
        _ = scrub.update(translation: CGSize(width: 500, height: 0), feedback: nil, hapticsEnabled: false)
        let back = scrub.update(translation: CGSize(width: 480, height: 0), feedback: nil, hapticsEnabled: false)
        XCTAssertEqual(back.target, 980, accuracy: 0.001)
    }

    func testTierBoundaries() {
        XCTAssertEqual(ScrubRateTier.tier(forVerticalDistance: 0), .hiSpeed)
        XCTAssertEqual(ScrubRateTier.tier(forVerticalDistance: 49), .hiSpeed)
        XCTAssertEqual(ScrubRateTier.tier(forVerticalDistance: 50), .half)
        XCTAssertEqual(ScrubRateTier.tier(forVerticalDistance: 100), .quarter)
        XCTAssertEqual(ScrubRateTier.tier(forVerticalDistance: 150), .fine)
        XCTAssertEqual(ScrubRateTier.tier(forVerticalDistance: -150), .fine)
    }
}

// MARK: - Coaching

@MainActor
final class GestureCoachTests: XCTestCase {

    private func geometry(usesTouch: Bool = true, size: CGSize = CGSize(width: 852, height: 393)) -> GestureGeometry {
        var capabilities = GestureCapabilities()
        capabilities.usesTouch = usesTouch
        return GestureGeometry(surface: SurfaceGeometry(size: size), capabilities: capabilities)
    }

    func testPresentsOnAFreshInstall() {
        XCTAssertTrue(
            GestureCoachModel.shouldPresent(
                policy: .firstRun,
                completedVersion: 0,
                shownCount: 0,
                assistive: AssistiveTechnologyState(),
                geometry: geometry(),
                availableSides: [.leading, .trailing]
            )
        )
    }

    func testDoesNotPresentOnceCompleted() {
        XCTAssertFalse(
            GestureCoachModel.shouldPresent(
                policy: .firstRun,
                completedVersion: GestureCoachModel.currentVersion,
                shownCount: 1,
                assistive: AssistiveTechnologyState(),
                geometry: geometry(),
                availableSides: [.trailing]
            )
        )
    }

    func testStopsAfterThePresentationCap() {
        XCTAssertFalse(
            GestureCoachModel.shouldPresent(
                policy: .firstRun,
                completedVersion: 0,
                shownCount: GestureCoachModel.maximumPresentations,
                assistive: AssistiveTechnologyState(),
                geometry: geometry(),
                availableSides: [.trailing]
            )
        )
    }

    /// Teaching a swipe to someone who cannot emit one steals focus and teaches
    /// nothing.
    func testSuppressedUnderAssistiveTechnology() {
        var assistive = AssistiveTechnologyState()
        assistive.isVoiceOverRunning = true

        XCTAssertFalse(
            GestureCoachModel.shouldPresent(
                policy: .firstRun,
                completedVersion: 0,
                shownCount: 0,
                assistive: assistive,
                geometry: geometry(),
                availableSides: [.trailing]
            )
        )
    }

    func testNeverPresentsInAThumbnailEmbed() {
        XCTAssertFalse(
            GestureCoachModel.shouldPresent(
                policy: .firstRun,
                completedVersion: 0,
                shownCount: 0,
                assistive: AssistiveTechnologyState(),
                geometry: geometry(size: CGSize(width: 200, height: 120)),
                availableSides: [.trailing]
            )
        )
    }

    /// A pointer user has no swipe to be taught.
    func testNeverPresentsOnAPointerSurface() {
        XCTAssertFalse(
            GestureCoachModel.shouldPresent(
                policy: .firstRun,
                completedVersion: 0,
                shownCount: 0,
                assistive: AssistiveTechnologyState(),
                geometry: geometry(usesTouch: false),
                availableSides: [.trailing]
            )
        )
    }

    func testAlwaysPolicyIgnoresPersistence() {
        XCTAssertTrue(
            GestureCoachModel.shouldPresent(
                policy: .always,
                completedVersion: GestureCoachModel.currentVersion,
                shownCount: 99,
                assistive: AssistiveTechnologyState(),
                geometry: geometry(),
                availableSides: [.trailing]
            )
        )
    }

    func testDisabledPolicyIsCheckedFirst() {
        XCTAssertFalse(
            GestureCoachModel.shouldPresent(
                policy: .disabled,
                completedVersion: 0,
                shownCount: 0,
                assistive: AssistiveTechnologyState(),
                geometry: geometry(),
                availableSides: [.trailing]
            )
        )
    }

    /// A tutorial that was *interrupted* is not a tutorial that was seen. The
    /// user's most likely first action is tapping to see the controls, and that
    /// must not burn the flag.
    func testAStrayEarlyTapDoesNotMarkTheCoachCompleted() {
        XCTAssertFalse(GestureCoachModel.marksCompleted(.touched, elapsed: 0.4))
        XCTAssertTrue(GestureCoachModel.marksCompleted(.touched, elapsed: 2.0))
        XCTAssertTrue(GestureCoachModel.marksCompleted(.timeout, elapsed: 0))
        XCTAssertTrue(GestureCoachModel.marksCompleted(.performed, elapsed: 0))
        XCTAssertFalse(GestureCoachModel.marksCompleted(.hostDisabled, elapsed: 99))
    }

    /// The count is written on show, so a crash mid-tutorial cannot re-show it
    /// forever.
    func testShownCountIsPersistedImmediatelyOnShow() {
        let defaults = UserDefaults(suiteName: "PlayerKitGestureCoachTests")!
        defaults.removePersistentDomain(forName: "PlayerKitGestureCoachTests")

        let clock = TestClock()
        let coach = GestureCoachModel(clock: clock)
        coach.defaults = defaults
        coach.assistiveProbe = { AssistiveTechnologyState() }

        coach.present(capabilities: GestureCapabilities(), geometry: geometry())

        XCTAssertEqual(defaults.integer(forKey: GestureCoachModel.DefaultsKey.shownCount), 1)
        XCTAssertNotNil(coach.stage)

        coach.dismiss(.timeout)
        XCTAssertNil(coach.stage)
        XCTAssertEqual(
            defaults.integer(forKey: GestureCoachModel.DefaultsKey.seenVersion),
            GestureCoachModel.currentVersion
        )
    }
}

// MARK: - Confusion detection

@MainActor
final class GestureConfusionDetectorTests: XCTestCase {

    func testAbandonedSwipeIsNoticed() {
        let detector = GestureConfusionDetector()
        XCTAssertEqual(
            detector.noteAdjustAttempt(kind: .volume, side: .trailing, travel: 8),
            .abandonedAdjustAttempt(.volume, .trailing)
        )
    }

    func testARealAdjustmentIsNotTreatedAsConfusion() {
        let detector = GestureConfusionDetector()
        XCTAssertNil(detector.noteAdjustAttempt(kind: .volume, side: .trailing, travel: 120))
    }

    func testRepeatedTapsInOneHalfTriggerANudge() {
        let detector = GestureConfusionDetector()
        XCTAssertNil(detector.noteTap(side: .trailing, now: 0))
        XCTAssertNil(detector.noteTap(side: .trailing, now: 1))
        XCTAssertEqual(detector.noteTap(side: .trailing, now: 2), .repeatedTapWithoutSwipe(.trailing))
    }

    /// Someone who has already used a rail is not confused about it.
    func testNoNudgeForSomeoneWhoHasAlreadyUsedTheRail() {
        let detector = GestureConfusionDetector()
        detector.noteRailEngaged()
        XCTAssertNil(detector.noteTap(side: .trailing, now: 0))
        XCTAssertNil(detector.noteTap(side: .trailing, now: 1))
        XCTAssertNil(detector.noteTap(side: .trailing, now: 2))
    }

    func testTapsOutsideTheWindowDoNotAccumulate() {
        let detector = GestureConfusionDetector()
        XCTAssertNil(detector.noteTap(side: .trailing, now: 0))
        XCTAssertNil(detector.noteTap(side: .trailing, now: 7))
        XCTAssertNil(detector.noteTap(side: .trailing, now: 14))
    }

    /// One nudge per playback session, at most.
    func testOnlyOneNudgePerSession() {
        let detector = GestureConfusionDetector()
        XCTAssertNotNil(detector.noteAdjustAttempt(kind: .volume, side: .trailing, travel: 5))
        XCTAssertNil(detector.noteAdjustAttempt(kind: .volume, side: .trailing, travel: 5))

        detector.resetSession()
        XCTAssertNotNil(detector.noteAdjustAttempt(kind: .volume, side: .trailing, travel: 5))
    }
}

// MARK: - Clock

@MainActor
final class GestureClockTests: XCTestCase {

    func testAdvanceFiresDueWorkInOrder() {
        let clock = TestClock()
        var fired: [String] = []
        clock.schedule(after: 0.5) { fired.append("b") }
        clock.schedule(after: 0.1) { fired.append("a") }

        clock.advance(by: 0.6)
        XCTAssertEqual(fired, ["a", "b"])
    }

    func testCancellationPreventsFiring() {
        let clock = TestClock()
        var fired = false
        let token = clock.schedule(after: 0.1) { fired = true }
        token.cancel()

        clock.advance(by: 1)
        XCTAssertFalse(fired)
        XCTAssertEqual(clock.pendingCount, 0)
    }

    /// Work scheduled *by* a callback inside the same window still runs, which
    /// is what a chained timer sequence depends on.
    func testNestedScheduleInsideTheSameWindowStillRuns() {
        let clock = TestClock()
        var fired: [String] = []
        clock.schedule(after: 0.1) {
            fired.append("outer")
            clock.schedule(after: 0.1) { fired.append("inner") }
        }

        clock.advance(by: 0.5)
        XCTAssertEqual(fired, ["outer", "inner"])
    }
}

// MARK: - Capability freshness

/// Capabilities decide which half drives which rail, so a stale snapshot is not
/// a cosmetic problem — it silently rewires the gesture.
@MainActor
final class GestureCapabilityFreshnessTests: XCTestCase {

    private final class FakeBackend: PlayerVolumeControlling {
        var outputVolume: Float = 0.5
        func setOutputVolume(_ value: Float) { outputVolume = value }
    }

    private let surface = SurfaceGeometry(size: CGSize(width: 852, height: 393))

    /// Regression: capabilities were computed once at `didMoveToWindow`, before
    /// any backend existed, so `volume` came back `.noBackend` and the trailing
    /// half fell through to brightness. Nothing recomputed them unless playback
    /// started, so with autoplay off the volume gesture never arrived at all.
    func testVolumeHalfPicksUpTheBackendWithoutWaitingForPlaybackToStart() {
        let manager = GestureManager(clock: TestClock())
        manager.updateSurface(surface)

        // The state at `didMoveToWindow`: a window, but no player yet.
        manager.refreshCapabilities()
        XCTAssertFalse(manager.currentCapabilities().volume.isAvailable)
        XCTAssertNotEqual(manager.geometry.kind(forSide: .trailing), .volume)

        let backend = FakeBackend()
        manager.volumeControl.backendProvider = { backend }

        let resolved = manager.resolvedGeometry(for: surface)
        XCTAssertTrue(resolved.capabilities.volume.isAvailable)
        XCTAssertEqual(
            resolved.kind(forSide: .trailing),
            .volume,
            "The rail the surface draws must reflect the backend that exists now"
        )
    }

    /// The router reads the cached geometry during a touch, so the cache has to
    /// be refreshed as the touch begins — and then held for its whole life.
    func testTouchBeginRefreshesTheCachedCapabilities() {
        let manager = GestureManager(clock: TestClock())
        manager.updateSurface(surface)
        manager.refreshCapabilities()
        XCTAssertNotEqual(manager.geometry.kind(forSide: .trailing), .volume)

        let backend = FakeBackend()
        manager.volumeControl.backendProvider = { backend }

        manager.touchesBegan(at: CGPoint(x: 700, y: 200), touchCount: 1, source: .touch)

        XCTAssertEqual(manager.geometry.kind(forSide: .trailing), .volume)
    }

    /// A host that turned the gesture off must not have it quietly reinstated by
    /// a refresh.
    func testHostDisabledVolumeStaysDisabledAcrossRefreshes() {
        let manager = GestureManager(clock: TestClock())
        manager.updateSurface(surface)
        let backend = FakeBackend()
        manager.volumeControl.backendProvider = { backend }

        var configuration = GestureConfiguration()
        configuration.isVolumeGestureEnabled = false
        manager.configuration = configuration

        manager.touchesBegan(at: CGPoint(x: 700, y: 200), touchCount: 1, source: .touch)

        XCTAssertEqual(manager.currentCapabilities().volume, .unavailable(.disabledByHost))
    }
}

// MARK: - Rail identity

/// What each rail *is*, and when the answer is allowed to change.
///
/// On a fresh launch the brightness control has no window yet — it only gets
/// one when the touch host lands in the hierarchy, which is after the gesture
/// surface's first render. `kind(forSide:)` deliberately falls back to volume
/// for an unavailable side (that is correct on macOS, where both halves drive
/// volume), so for one render the leading rail honestly resolves to volume.
/// The bug was that nothing ever repainted: the affordance kept the volume
/// glyph on both sides for the rest of the session while the drag underneath
/// drove brightness. The affordance leaf now re-renders off
/// `capabilitiesGeneration`, so these tests pin the two halves of that chain.
@MainActor
final class RailIdentityTests: XCTestCase {

    /// The fallback that produced the double-speaker screenshot.
    func testLeadingRailFallsBackToVolumeOnlyWhileBrightnessIsUnavailable() {
        var capabilities = GestureCapabilities()
        capabilities.volume = .available
        capabilities.brightness = .unavailable(.notSupportedOnPlatform)
        let withoutWindow = GestureGeometry(
            surface: SurfaceGeometry(size: CGSize(width: 800, height: 400)),
            capabilities: capabilities,
            railMapping: .brightnessLeading
        )
        XCTAssertEqual(withoutWindow.kind(forSide: .leading), .volume,
                       "No brightness anywhere: the leading rail may fall back")
        XCTAssertEqual(withoutWindow.kind(forSide: .trailing), .volume)

        capabilities.brightness = .available
        let withWindow = GestureGeometry(
            surface: SurfaceGeometry(size: CGSize(width: 800, height: 400)),
            capabilities: capabilities,
            railMapping: .brightnessLeading
        )
        XCTAssertEqual(withWindow.kind(forSide: .leading), .brightness,
                       "With brightness available the sides must differ again")
        XCTAssertEqual(withWindow.kind(forSide: .trailing), .volume)
    }

    /// The repaint signal: a capability change bumps the published generation
    /// exactly when the answer changes, so the affordance leaf redraws — and
    /// stays quiet when nothing changed, so it cannot re-render at touch rate.
    func testCapabilityRefreshPublishesExactlyOnRealChanges() {
        let manager = GestureManager()
        manager.configuration.isEnabled = true
        manager.refreshCapabilities()
        let baseline = manager.capabilitiesGeneration

        manager.refreshCapabilities()
        XCTAssertEqual(manager.capabilitiesGeneration, baseline,
                       "No change, no publish")

        manager.configuration.isVolumeGestureEnabled.toggle()
        // configuration.didSet refreshes on its own; assert the bump landed.
        XCTAssertGreaterThan(manager.capabilitiesGeneration, baseline,
                             "A real capability change must publish")
    }
}
