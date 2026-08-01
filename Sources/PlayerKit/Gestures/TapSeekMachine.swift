import CoreGraphics
import Foundation

/// The tap state machine: single tap toggles, double tap on a side starts an
/// accumulating skip session, further single taps keep skipping.
///
/// Extracted from `GestureManager` so it can be exercised without a view, a
/// window or a run loop. The behaviour it encodes has three jobs that pull
/// against each other — a single tap has to toggle the controls immediately, a
/// second tap on the same side has to take that toggle back and start skipping,
/// and once a session is open plain single taps have to keep skipping instead of
/// toggling — and each of those is pinned by test.
final class TapSeekMachine {

    // MARK: - Wiring

    var emit: ((GestureIntent) -> Void)?
    var isLockedProvider: () -> Bool = { false }
    var currentTimeProvider: () -> Double? = { nil }

    /// The window a skip may land in.
    ///
    /// This used to be a `durationProvider`, which made live streams jump to the
    /// start: `duration` is 0 for live/DVR HLS, so clamping with
    /// `min(duration, …)` clamped every skip to zero. The seekable range is
    /// `0...duration` for VOD and the DVR window for live, so one provider
    /// serves both. `nil` means there is nothing to seek within.
    var seekableRangeProvider: () -> ClosedRange<Double>? = { nil }

    /// Whether the chrome is on screen right now.
    ///
    /// Unwired it reports `true`, which is exactly the behaviour every existing
    /// test encodes, so the deferred-toggle path below is opt-in per host rather
    /// than a silent behaviour change.
    var areControlsVisibleProvider: () -> Bool = { true }

    var feedback: GestureFeedbackPerforming?
    var isHapticsEnabled = true

    // MARK: - Tuning

    /// Seconds one skip covers.
    var skipInterval: Double = 10
    /// How long a second tap has to arrive to count as a double tap. Relaxed
    /// under Switch Control and AssistiveTouch, where 0.28s is not reachable.
    var doubleTapWindow: TimeInterval = 0.28
    /// How long the seek session stays open after the last tap. Within it a
    /// plain single tap keeps skipping instead of toggling the controls.
    let seekSessionTimeout: TimeInterval = 0.75

    // MARK: - State

    private enum TapPhase {
        case idle
        /// One tap has landed. A second tap in the same side zone, before the
        /// double-tap window closes, starts a seek session.
        case awaitingSecondTap(zone: TapZone)
        /// A seek session is open; every further tap accumulates.
        case seeking(direction: SeekDirection)
    }

    private let clock: GestureClock
    private var tapPhase: TapPhase = .idle
    private var accumulatedInterval: Double = 0
    /// Counts the taps in the running session, so the overlay can tell one from
    /// the next and replay its per-tap animation.
    private var tapCounter: Int = 0
    private var doubleTapTimer: GestureCancellable?
    private var seekSessionTimer: GestureCancellable?

    /// The playhead the session started from. Every skip is applied to this
    /// rather than to the live position, so the total never drifts when seeks
    /// land asynchronously.
    private var initialTime: Double?

    /// The last target actually issued, clamped.
    ///
    /// This is the anchor a reversal re-bases on, and it is the whole fix for
    /// the worst bug in the old machine: reversing re-read `currentTimeProvider`,
    /// which on every real backend still reports the *pre-seek* position because
    /// seeks are asynchronous. Three fast forward taps from 100 issued seeks to
    /// 110/120/130, then a back tap read ~102 and seeked to 92 while the overlay
    /// read "10 seconds" — a 38-second regression labelled as ten. The old tests
    /// could not see it because their probe applied seeks synchronously, which
    /// is the one thing no real player does.
    private var committedTarget: Double?

    /// True while a second tap could still arrive. The chrome drops hit testing
    /// on this so the second tap of a double tap cannot land on a button that
    /// the first tap just faded in.
    private(set) var isAwaitingSecondTap = false

    private var currentOverlay: DoubleTapSeekOverlayState?
    /// A toggle held back to see whether a second tap follows.
    private var pendingToggle = false

    init(clock: GestureClock) {
        self.clock = clock
    }

    deinit {
        doubleTapTimer?.cancel()
        seekSessionTimer?.cancel()
    }

    var isSeeking: Bool { currentOverlay != nil }
    var overlay: DoubleTapSeekOverlayState? { currentOverlay }

    // MARK: - Entry points

    /// Routes one tap through the machine.
    ///
    /// A single tap toggles the controls immediately rather than being held back
    /// for the whole double-tap window, which is what made the controls feel a
    /// beat late. The one exception is a tap that could be the first half of a
    /// skip while the chrome is *hidden*: showing it there would wash the entire
    /// interface in and straight back out behind the skip, so that specific
    /// show is deferred.
    func handleTap(unitOrigin: CGPoint, zone: TapZone) {
        switch tapPhase {
        case .seeking(let currentDirection):
            guard let direction = zone.seekDirection else {
                // A tap in the dead zone leaves the session and behaves like an
                // ordinary single tap.
                endSeekSession()
                emit?(.toggleControls(.immediate))
                return
            }
            accumulateSkip(
                direction: direction,
                reversing: direction != currentDirection,
                unitOrigin: unitOrigin
            )

        case .awaitingSecondTap(let firstZone):
            invalidateDoubleTapTimer()
            tapPhase = .idle
            // Both taps have to land on the same side. Tapping left then right
            // is two single taps, not a skip.
            if zone == firstZone, let direction = zone.seekDirection, !isLocked() {
                // The deferred show is taken back rather than performed.
                pendingToggle = false
                beginSeekSession(direction: direction, unitOrigin: unitOrigin)
            } else {
                flushPendingToggle()
                emit?(.toggleControls(.immediate))
            }

        case .idle:
            tapPhase = .awaitingSecondTap(zone: zone)
            startDoubleTapTimer()
            // This tap may turn out to be the first half of a skip. Spin the
            // Taptic Engine up now so the hit on the second tap is not the one
            // that has to wait for it.
            if zone.seekDirection != nil, !isLocked() {
                feedback?.prepare(.light)
            }

            let controlsVisible = areControlsVisibleProvider()
            if zone.seekDirection != nil, !isLocked(), !controlsVisible {
                pendingToggle = true
                emit?(.toggleControls(.deferredUntilDoubleTapWindowCloses))
            } else {
                emit?(.toggleControls(.immediate))
            }
        }
    }

    /// A skip with no fingertip behind it — the ±10s buttons, a rotor action, a
    /// keyboard arrow, a remote command.
    ///
    /// Routed through the same accumulation as the double tap so there is one
    /// clamp, one overlay and one total, however the skip was asked for.
    func skip(_ direction: SeekDirection) {
        guard !isLocked() else {
            emit?(.blocked(.skip))
            return
        }
        let origin = CGPoint(x: direction == .forward ? 0.75 : 0.25, y: 0.5)
        switch tapPhase {
        case .seeking(let current):
            accumulateSkip(direction: direction, reversing: direction != current, unitOrigin: origin)
        case .idle, .awaitingSecondTap:
            invalidateDoubleTapTimer()
            pendingToggle = false
            beginSeekSession(direction: direction, unitOrigin: origin)
        }
    }

    /// Drops any in-flight session and its timers.
    func reset() {
        pendingToggle = false
        endSeekSession()
    }

    // MARK: - Session

    private func beginSeekSession(direction: SeekDirection, unitOrigin: CGPoint) {
        // Validate *before* committing to the session. The old code hid the
        // controls first and only then discovered there was nothing to seek
        // within, so a double tap on a still-loading stream simply deleted the
        // interface: no overlay, no seek, no haptic, and nothing put the chrome
        // back.
        guard let start = currentTimeProvider(), seekableRangeProvider() != nil else {
            flushPendingToggle()
            emit?(.toggleControls(.immediate))
            return
        }

        accumulatedInterval = 0
        initialTime = start
        committedTarget = nil
        tapPhase = .seeking(direction: direction)
        accumulateSkip(direction: direction, reversing: false, unitOrigin: unitOrigin, isOpening: true)
    }

    private func accumulateSkip(
        direction: SeekDirection,
        reversing: Bool,
        unitOrigin: CGPoint,
        isOpening: Bool = false
    ) {
        guard !isLocked() else {
            endSeekSession()
            emit?(.toggleControls(.immediate))
            emit?(.blocked(.skip))
            return
        }

        guard seekableRangeProvider() != nil, initialTime != nil else {
            endSeekSession()
            emit?(.toggleControls(.immediate))
            emit?(.blocked(.skip))
            return
        }

        if reversing {
            // Turning around starts a fresh count from where the playhead is
            // *going*, not from where it currently reads, so a back-tap after
            // "forward 30" reads 10 and lands 10 back from 130.
            accumulatedInterval = 0
            initialTime = committedTarget ?? currentTimeProvider() ?? initialTime
            committedTarget = nil
            tapPhase = .seeking(direction: direction)
        }

        accumulatedInterval += skipInterval
        let achieved = performSeek(direction: direction)

        guard achieved > 0.01 else {
            // Already hard against the end of the seekable window. Take the
            // increment back so the readout stops climbing past a skip that
            // cannot happen, and say nothing rather than advertising it.
            accumulatedInterval -= skipInterval
            if isOpening {
                endSeekSession()
                emit?(.toggleControls(.immediate))
                emit?(.blocked(.skip))
            } else {
                restartSeekSessionTimer()
            }
            return
        }

        if isOpening {
            // The first tap of the pair deferred or performed its toggle;
            // skipping puts the chrome away so the overlay has the screen to
            // itself. Only after a skip has actually succeeded.
            emit?(.setControlsVisible(false))
        }

        tapCounter += 1
        setOverlay(
            DoubleTapSeekOverlayState(
                direction: direction,
                seconds: accumulatedInterval,
                unitOrigin: unitOrigin,
                tapID: tapCounter
            )
        )
        if isHapticsEnabled { feedback?.impact(.light) }
        restartSeekSessionTimer()
    }

    /// Seeks to the anchor plus the accumulated offset, clamped into the
    /// seekable window, and reports how much movement that actually bought.
    ///
    /// Returning the achieved delta rather than a bool is what lets the caller
    /// tell "skipped ten seconds" from "was already at the end".
    private func performSeek(direction: SeekDirection) -> Double {
        guard let anchor = initialTime,
              let seekableRange = seekableRangeProvider() else { return 0 }

        let offset = direction == .forward ? accumulatedInterval : -accumulatedInterval
        let newTime = min(
            max(anchor + offset, seekableRange.lowerBound),
            seekableRange.upperBound
        )

        let previous = committedTarget ?? anchor
        let achieved = abs(newTime - previous)
        guard achieved > 0.01 else { return 0 }

        committedTarget = newTime
        emit?(.seek(to: newTime))
        return achieved
    }

    /// The single writer for the overlay.
    ///
    /// Two jobs beyond the assignment: skip the write when nothing changed, so
    /// ending a session that was already closed does not publish to every
    /// observer for nothing, and report open/close transitions — and only
    /// transitions — as a session change.
    private func setOverlay(_ newValue: DoubleTapSeekOverlayState?) {
        guard currentOverlay != newValue else { return }
        let wasActive = currentOverlay != nil
        currentOverlay = newValue
        emit?(.skipOverlay(newValue))
        let isActive = newValue != nil
        if wasActive != isActive {
            emit?(.seekSession(isOpen: isActive))
        }
    }

    private func endSeekSession() {
        invalidateSeekSessionTimer()
        invalidateDoubleTapTimer()
        tapPhase = .idle
        accumulatedInterval = 0
        tapCounter = 0
        initialTime = nil
        committedTarget = nil
        setOverlay(nil)
    }

    // MARK: - Timers

    private func startDoubleTapTimer() {
        invalidateDoubleTapTimer()
        isAwaitingSecondTap = true
        doubleTapTimer = clock.schedule(after: doubleTapWindow) { [weak self] in
            guard let self else { return }
            if case .awaitingSecondTap = self.tapPhase {
                self.tapPhase = .idle
            }
            self.invalidateDoubleTapTimer()
            // No second tap arrived, so the held-back show happens now.
            self.flushPendingToggle()
        }
    }

    private func invalidateDoubleTapTimer() {
        doubleTapTimer?.cancel()
        doubleTapTimer = nil
        isAwaitingSecondTap = false
    }

    private func flushPendingToggle() {
        guard pendingToggle else { return }
        pendingToggle = false
        emit?(.toggleControls(.immediate))
    }

    private func restartSeekSessionTimer() {
        invalidateSeekSessionTimer()
        seekSessionTimer = clock.schedule(after: seekSessionTimeout) { [weak self] in
            self?.endSeekSession()
        }
    }

    private func invalidateSeekSessionTimer() {
        seekSessionTimer?.cancel()
        seekSessionTimer = nil
    }

    private func isLocked() -> Bool {
        isLockedProvider()
    }
}
