import CoreGraphics
import Foundation

/// Routing one touch, from the platform's raw events to an effect.
///
/// This is the layer that used to be a `DragGesture(minimumDistance: 0)` with a
/// `@State private var isPanning`. Three things changed and all three matter:
/// the touch is classified **once**, at the slop threshold, and then owned to
/// completion; the platform delivers a real **cancel** when a system gesture
/// steals the sequence, so a half-finished swipe cannot commit; and the value
/// fed to a rail is **engagement-relative**, so engaging no longer lurches the
/// level by a slop's worth.
extension GestureManager {

    // MARK: - Touch entry points

    func touchesBegan(at location: CGPoint, touchCount: Int, source: PointerSource) {
        guard configuration.isEnabled else { return }

        // Resolved once per touch and then held for its whole life, so a
        // backend that finishes loading mid-gesture cannot change what the
        // finger is driving underneath it.
        refreshCapabilities()

        if touchCount > 1 {
            // A second finger means a pinch. Abandon the drag path outright so
            // it can never also land as a tap or ride a rail.
            abandonTouch()
            classifier.noteAdditionalTouch(count: touchCount)
            return
        }

        coach.noteTouch()
        classifier.begin(
            at: location,
            touchCount: touchCount,
            now: clock.now,
            tuning: tuning(),
            source: source
        )

        cancelTouchTimers()
        guard source == .touch else { return }

        // Tier 1: reveal the rail under a resting finger, before any travel.
        // Free probing is the only mechanism here that teaches the gesture to
        // someone who was never told it exists.
        if let side = geometry.railSide(for: location),
           geometry.isPanEligible(location),
           let kind = geometry.kind(forSide: side),
           control(for: kind)?.availability.isAvailable == true,
           !isLocked() {
            armToken = clock.schedule(after: tuning().armDelay) { [weak self] in
                guard let self, self.classifier.promoteToArmed() else { return }
                self.armRail(kind: kind, side: side)
            }
        }

        if configuration.isSpeedHoldEnabled {
            holdToken = clock.schedule(after: tuning().holdDuration) { [weak self] in
                guard let self, self.classifier.promoteToHold() else { return }
                self.beginSpeedHold()
            }
        }
    }

    func touchesMoved(to location: CGPoint, touchCount: Int) {
        guard configuration.isEnabled, classifier.isActive else { return }
        guard touchCount <= 1 else { return abandonTouch() }

        let translation = CGSize(
            width: location.x - classifier.startLocation.x,
            height: location.y - classifier.startLocation.y
        )

        let didResolve = classifier.update(
            translation: translation,
            touchCount: touchCount,
            now: clock.now,
            context: classificationContext()
        )

        if didResolve {
            cancelTouchTimers()
            beginResolvedGesture(at: location)
        }

        driveResolvedGesture(at: location, translation: translation)
    }

    func touchesEnded(at location: CGPoint, touchCount: Int) {
        cancelTouchTimers()
        guard let outcome = classifier.finish(cancelled: false) else { return }
        finishGesture(outcome, at: location, cancelled: false)
    }

    /// The signal a SwiftUI `DragGesture` never gave us.
    ///
    /// Delivered when a system recogniser claims the sequence: a screen-edge
    /// swipe, Notification Centre, the Slide Over divider, an incoming call
    /// banner. Every one of those used to leave a half-applied gesture behind.
    func touchesCancelled() {
        cancelTouchTimers()
        guard let outcome = classifier.finish(cancelled: true) else { return }
        finishGesture(outcome, at: classifier.startLocation, cancelled: true)
    }

    // MARK: - Resolution

    private func beginResolvedGesture(at location: CGPoint) {
        switch classifier.outcome {
        case .verticalRail(let side):
            guard let kind = geometry.kind(forSide: side),
                  let control = control(for: kind) else { return }
            guard !isLocked() else { return blockGesture(kind) }
            rail.begin(kind: kind, control: control, at: location, now: clock.now)
            activeRailKind = kind
            activeRailSide = side
            coachDidObserveRailEngagement()
            if configuration.isHapticsEnabled { feedbackPerformer.impact(.light) }
            emit(.axisLocked)
            emit(.levelBegan(kind, side))

        case .horizontalScrub:
            guard !isLocked() else { return blockGesture(.scrub) }
            guard let range = seekableRangeProvider?(), let current = currentTimeProvider?() else { return }
            scrub.begin(
                from: current,
                range: range,
                secondsPerPoint: geometry.secondsPerPoint(span: range.upperBound - range.lowerBound),
                engagementTranslation: classifier.engagementTranslation
            )
            if configuration.isHapticsEnabled { feedbackPerformer.impact(.light) }
            emit(.axisLocked)
            emit(.scrubBegan)

        case .inert(let reason):
            // Never silence. The touch still resolves as a tap on lift, but the
            // user is told why the gesture they meant is not there.
            PlayerKitLog.debug("Gestures", "Gesture unavailable: \(reason)")

        case .speedHold, .tap, .undecided:
            break
        }
    }

    private func driveResolvedGesture(at location: CGPoint, translation: CGSize) {
        switch classifier.outcome {
        case .verticalRail(let side):
            guard let kind = activeRailKind, let control = control(for: kind) else { return }
            let dy = translation.height - classifier.engagementTranslation.height
            let sample = rail.update(
                dy: dy,
                at: location,
                now: clock.now,
                travel: geometry.fullRangeTravel,
                control: control,
                feedback: feedbackPerformer,
                hapticsEnabled: configuration.isHapticsEnabled
            )
            guard sample.didChange else { return }
            presentRail(kind: kind, side: side, unit: sample.unit, isArmed: false, isPinned: sample.isPinned)
            emit(.levelChanged(kind, unit: sample.unit))
            if sample.isPinned {
                emit(.levelPinned(kind, atMaximum: sample.unit >= 1))
            }

        case .horizontalScrub:
            let sample = scrub.update(
                translation: translation,
                feedback: feedbackPerformer,
                hapticsEnabled: configuration.isHapticsEnabled
            )
            presentScrub(sample)
            emit(.scrubChanged(offsetSeconds: sample.delta, tier: sample.tier))

        case .speedHold, .tap, .inert, .undecided:
            break
        }
    }

    private func finishGesture(_ outcome: TouchOutcome, at location: CGPoint, cancelled: Bool) {
        switch outcome {
        case .tap:
            // A finger that lingered long enough to arm a rail and then lifted
            // without moving is still a tap — but the revealed rail has to go,
            // or probing leaves a ghost readout on screen for the rest of the
            // session.
            dismissArmedRailIfNeeded()
            guard !cancelled else { return }
            noteTapForConfusion(at: location)
            handleTap(at: location, in: geometry.size)

        case .verticalRail(let side):
            if let kind = activeRailKind, let control = control(for: kind) {
                // Flush the final value past the frame gate, so lifting between
                // two gated frames cannot leave the control a step behind the
                // rail the user was looking at.
                rail.end(control: control)
                announceRail(kind: kind)
                noteAbandonedAttempt(kind: kind, side: side)
            }
            activeRailKind = nil
            activeRailSide = nil
            hudModel.beginDwell()

        case .horizontalScrub:
            if cancelled {
                // A cancelled scrub issues **zero** seeks.
                scrub.cancel()
                emit(.scrubEnded(committedTarget: nil))
                hudModel.clearImmediately()
            } else {
                let target = scrub.commitTarget()
                scrub.end()
                emit(.scrubEnded(committedTarget: target))
                emit(.seek(to: target))
                hudModel.beginDwell()
            }

        case .speedHold:
            endSpeedHold()

        case .inert:
            // Fall-through: a drag whose gesture is unavailable still resolves
            // as a tap, so there is no configuration in which a drag on the
            // video does nothing at all.
            dismissArmedRailIfNeeded()
            guard !cancelled else { return }
            handleTap(at: location, in: geometry.size)

        case .undecided:
            if activeRailKind != nil { rail.cancel() }
            if scrub.isActive { scrub.cancel() }
            activeRailKind = nil
            activeRailSide = nil
            endSpeedHold()
            hudModel.clearImmediately()
        }
    }

    /// Fades out a rail that was revealed under a resting finger but never
    /// committed to. Without this, a probe leaves a readout on screen showing a
    /// value nothing is driving.
    func dismissArmedRailIfNeeded() {
        guard hudModel.hud?.isArmed == true else { return }
        hudModel.beginDwell()
    }

    /// Drops the in-flight touch without committing anything.
    func abandonTouch() {
        cancelTouchTimers()
        dismissArmedRailIfNeeded()
        _ = classifier.finish(cancelled: true)
        if activeRailKind != nil { rail.cancel() }
        if scrub.isActive {
            scrub.cancel()
            emit(.scrubEnded(committedTarget: nil))
        }
        activeRailKind = nil
        activeRailSide = nil
        endSpeedHold()
        emit(.cancel)
    }

    // MARK: - Pinch

    func pinchChanged(scale: CGFloat, phase: PinchPhase) {
        guard configuration.isZoomGestureEnabled else { return }
        switch phase {
        case .began:
            abandonTouch()
        case .changed:
            guard !isLocked() else { return }
            // Hysteresis, so a hand that settles just past the threshold does
            // not flip fit/fill on every frame.
            if scale >= 1.12, lastZoomFill != true {
                lastZoomFill = true
                applyZoom(fill: true)
            } else if scale <= 0.89, lastZoomFill != false {
                lastZoomFill = false
                applyZoom(fill: false)
            }
        case .ended, .cancelled:
            lastZoomFill = nil
        }
    }

    private func applyZoom(fill: Bool) {
        onZoom?(fill ? 1.5 : 0.5)
        emit(.zoom(fill: fill))
        if configuration.isHapticsEnabled { feedbackPerformer.impact(.light) }
        hudModel.set(
            GestureHUD(
                kind: .zoom,
                slot: .banner,
                symbol: fill ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                primary: fill ? "Fill" : "Fit",
                secondary: nil,
                tertiary: nil,
                fraction: nil
            )
        )
        hudModel.beginDwell()
    }

    // MARK: - Two-finger tap

    func twoFingerTap() {
        guard configuration.isTwoFingerPlayPauseEnabled, !isLocked() else { return }
        emit(.togglePlayback)
        let willPlay = !(isPlayingProvider?() ?? false)
        if configuration.isHapticsEnabled { feedbackPerformer.impact(.light) }
        hudModel.set(
            GestureHUD(
                kind: .playPause,
                slot: .banner,
                symbol: willPlay ? "play.fill" : "pause.fill",
                primary: willPlay ? "Play" : "Pause",
                secondary: nil,
                tertiary: nil,
                fraction: nil
            )
        )
        hudModel.beginDwell()
    }

    // MARK: - Speed hold

    private func beginSpeedHold() {
        guard speedHold.engage(feedback: feedbackPerformer, hapticsEnabled: configuration.isHapticsEnabled) else { return }
        emit(.speedHoldBegan)
        hudModel.set(
            GestureHUD(
                kind: .speed,
                slot: .banner,
                symbol: "forward.fill",
                primary: Self.speedLabel(speedHold.engagedSpeed),
                secondary: nil,
                tertiary: nil,
                fraction: nil
            )
        )
    }

    func endSpeedHold() {
        guard speedHold.release(feedback: feedbackPerformer, hapticsEnabled: configuration.isHapticsEnabled) else { return }
        emit(.speedHoldEnded)
        hudModel.beginDwell()
    }

    static func speedLabel(_ speed: Float) -> String {
        let rounded = (speed * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        return String(format: "%.1f×", rounded)
    }

    // MARK: - Rail presentation

    private func armRail(kind: GestureKind, side: RailSide) {
        guard let control = control(for: kind) else { return }
        control.refreshBaseline()
        presentRail(kind: kind, side: side, unit: control.readLevel(), isArmed: true, isPinned: false)
        emit(.levelArmed(kind, side))
    }

    private func announceRail(kind: GestureKind) {
        guard let hud = hudModel.hud else { return }
        GestureAnnouncer.announce(hud.accessibilityAnnouncement, state: assistiveState)
    }

    private func blockGesture(_ kind: GestureKind) {
        emit(.blocked(kind))
    }

    // MARK: - Context

    private func classificationContext() -> ClassificationContext {
        ClassificationContext(
            railAvailability: { [weak self] side in
                guard let self else { return .unavailable(.disabledByHost) }
                guard !self.isLocked() else { return .unavailable(.disabledByHost) }
                guard let kind = self.geometry.kind(forSide: side) else {
                    return .unavailable(.notSupportedOnPlatform)
                }
                return self.control(for: kind)?.availability ?? .unavailable(.noBackend)
            },
            isScrubAvailable: !isLocked()
                && configuration.isScrubGestureEnabled
                && seekableRangeProvider?() != nil,
            startSide: geometry.railSide(for: classifier.startLocation),
            isPanEligible: geometry.isPanEligible(classifier.startLocation)
        )
    }

    func tuning() -> TouchClassifier.Tuning {
        var tuning = TouchClassifier.Tuning()
        if assistiveState.needsRelaxedTiming {
            tuning.holdDuration = 0.9
        }
        return tuning
    }

    func cancelTouchTimers() {
        armToken?.cancel()
        armToken = nil
        holdToken?.cancel()
        holdToken = nil
    }
}

// MARK: - Location-free entry points

/// Every gesture reachable without a `CGPoint`.
///
/// This is what makes the layer usable from a rotor action, a keyboard, a
/// remote command or a visible button. The old code demanded a touch location
/// at every entry point, which is why none of these gestures had an accessible
/// equivalent at all.
extension GestureManager {

    func nudge(_ kind: GestureKind, _ direction: AdjustDirection) {
        guard let control = control(for: kind), control.availability.isAvailable else { return }
        guard !isLocked() else { return emit(.blocked(kind)) }
        control.refreshBaseline()
        let step = control.writeQuantum
        let next = min(max(control.readLevel() + (direction == .increment ? step : -step), 0), 1)
        control.setLevel(next)
        let side = railSide(driving: kind) ?? .trailing
        presentRail(kind: kind, side: side, unit: next, isArmed: false, isPinned: next <= 0 || next >= 1)
        hudModel.beginDwell()
        if configuration.isHapticsEnabled { feedbackPerformer.selection() }
        GestureAnnouncer.announce(hudModel.hud?.accessibilityAnnouncement ?? "", state: assistiveState)
    }

    func setLevel(_ kind: GestureKind, _ value: Double) {
        guard let control = control(for: kind), control.availability.isAvailable else { return }
        guard !isLocked() else { return emit(.blocked(kind)) }
        let clamped = min(max(value, 0), 1)
        control.setLevel(clamped)
        let side = railSide(driving: kind) ?? .trailing
        presentRail(kind: kind, side: side, unit: clamped, isArmed: false, isPinned: clamped <= 0 || clamped >= 1)
        hudModel.beginDwell()
    }

    func level(of kind: GestureKind) -> Double {
        control(for: kind)?.readLevel() ?? 0
    }

    func railSide(driving kind: GestureKind) -> RailSide? {
        RailSide.allCases.first { geometry.kind(forSide: $0) == kind }
    }

    func toggleZoom() {
        guard configuration.isZoomGestureEnabled, !isLocked() else { return }
        isZoomFilled.toggle()
        applyZoomPublic(fill: isZoomFilled)
    }

    func toggleControls() {
        emit(.toggleControls(.immediate))
    }

    func togglePlayback() {
        twoFingerTap()
    }

    // MARK: - Scroll wheel (macOS)

    /// The first reachable desktop path to volume. On a machine with no
    /// touchscreen the old layer offered none at all.
    func scrollWheel(at location: CGPoint, delta: CGSize, phase: ScrollPhase) {
        guard configuration.isEnabled, !isLocked() else { return }
        if phase == .began { refreshCapabilities() }
        guard abs(delta.height) >= 1 else { return }
        guard let side = geometry.railSide(for: location),
              let kind = geometry.kind(forSide: side),
              let control = control(for: kind),
              control.availability.isAvailable else { return }

        if phase == .began || scrollRailKind != kind {
            control.refreshBaseline()
            scrollRailKind = kind
            scrollRailSide = side
        }

        let step = Double(delta.height) / Double(geometry.fullRangeTravel)
        let next = min(max(control.readLevel() + step, 0), 1)
        control.setLevel(next)
        presentRail(kind: kind, side: side, unit: next, isArmed: false, isPinned: next <= 0 || next >= 1)

        scrollIdleToken?.cancel()
        if phase == .ended {
            endScrollRail()
        } else {
            scrollIdleToken = clock.schedule(after: 0.70) { [weak self] in
                self?.endScrollRail()
            }
        }
    }

    private func endScrollRail() {
        scrollIdleToken?.cancel()
        scrollIdleToken = nil
        scrollRailKind = nil
        scrollRailSide = nil
        hudModel.beginDwell()
    }

    func applyZoomPublic(fill: Bool) {
        onZoom?(fill ? 1.5 : 0.5)
        emit(.zoom(fill: fill))
        if configuration.isHapticsEnabled { feedbackPerformer.impact(.light) }
        hudModel.set(
            GestureHUD(
                kind: .zoom,
                slot: .banner,
                symbol: fill ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                primary: fill ? "Fill" : "Fit",
                secondary: nil,
                tertiary: nil,
                fraction: nil
            )
        )
        hudModel.beginDwell()
    }
}
