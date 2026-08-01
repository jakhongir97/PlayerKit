import CoreGraphics
import Foundation
import QuartzCore

/// Drives one output level from vertical travel.
///
/// Pure arithmetic plus two gates; every platform detail is behind
/// `OutputLevelControlling`, so the mapping, the quantisation and the haptic
/// grammar are all assertable without a device.
final class VerticalRailController {

    struct RailSample: Equatable {
        /// Logical value, 0…1.
        let unit: Double
        /// Quantised to 1/32 for display, so the readout does not flicker
        /// between two integers that round differently.
        let displayStep: Int
        let isPinned: Bool
        let didChange: Bool
    }

    /// Above this the finger is travelling too fast for individual ticks to read
    /// as anything but a buzz.
    private static let hapticVelocityCeiling: CGFloat = 600
    private static let hapticQuantum: Double = 1.0 / 16.0
    private static let displayQuantum: Double = 1.0 / 32.0

    private var baseline: Double = 0
    private var current: Double = 0
    private var gate = LevelWriteGate(quantum: 1.0 / 16.0)
    private var lastHapticStep: Int = .min
    /// `nil` while free, `true`/`false` once latched at the top or bottom, so
    /// the end-stop thud fires once instead of on every further event.
    private var pinnedLatch: Bool?
    private var lastLocation: CGPoint = .zero
    private var lastMoveTime: CFTimeInterval = 0
    private(set) var isActive = false

    /// Captured at touch **down**.
    ///
    /// The old code captured it in the gesture's `onEnded`, so anything that
    /// changed the level between two swipes — the hardware buttons, Control
    /// Centre, auto-brightness — left the next swipe's first frame jumping from
    /// a stale baseline.
    func begin(kind: GestureKind, control: OutputLevelControlling, at location: CGPoint, now: CFTimeInterval) {
        control.refreshBaseline()
        baseline = control.readLevel()
        current = baseline
        gate = LevelWriteGate(quantum: control.writeQuantum)
        lastHapticStep = Int((baseline / Self.hapticQuantum).rounded())
        pinnedLatch = baseline >= 1 ? true : (baseline <= 0 ? false : nil)
        lastLocation = location
        lastMoveTime = now
        isActive = true
    }

    /// `dy` is already engagement-relative — the classifier subtracts the travel
    /// spent crossing the slop, which is what removes the visible lurch the old
    /// code produced the instant a swipe engaged.
    @discardableResult
    func update(
        dy: CGFloat,
        at location: CGPoint,
        now: CFTimeInterval,
        travel: CGFloat,
        control: OutputLevelControlling,
        feedback: GestureFeedbackPerforming?,
        hapticsEnabled: Bool
    ) -> RailSample {
        guard isActive, travel > 0 else {
            return RailSample(unit: current, displayStep: displayStep(current), isPinned: pinnedLatch != nil, didChange: false)
        }

        // Up is more.
        let proposed = baseline + Double(-dy / travel)
        let clamped = min(max(proposed, 0), 1)
        let didChange = clamped != current
        current = clamped

        if gate.shouldWrite(clamped, now: now) {
            control.setLevel(clamped)
        }

        if hapticsEnabled {
            emitHaptics(for: clamped, at: location, now: now, feedback: feedback)
        }
        lastLocation = location
        lastMoveTime = now

        return RailSample(
            unit: clamped,
            displayStep: displayStep(clamped),
            isPinned: clamped <= 0 || clamped >= 1,
            didChange: didChange
        )
    }

    /// Flushes the final value past the frame gate, so lifting between two gated
    /// frames cannot leave the control a step behind the rail the user saw.
    func end(control: OutputLevelControlling) {
        guard isActive else { return }
        isActive = false
        control.setLevel(current)
    }

    func cancel() {
        isActive = false
    }

    var currentValue: Double { current }

    // MARK: - Private

    private func displayStep(_ value: Double) -> Int {
        Int((value / Self.displayQuantum).rounded())
    }

    private func emitHaptics(
        for value: Double,
        at location: CGPoint,
        now: CFTimeInterval,
        feedback: GestureFeedbackPerforming?
    ) {
        // One thud when the value first reaches an end stop, latched so it does
        // not repeat while the finger keeps pushing into it.
        if value >= 1 || value <= 0 {
            let atMaximum = value >= 1
            if pinnedLatch != atMaximum {
                pinnedLatch = atMaximum
                feedback?.impact(.rigid)
            }
            return
        }
        pinnedLatch = nil

        let elapsed = now - lastMoveTime
        if elapsed > 0 {
            let velocity = abs(location.y - lastLocation.y) / CGFloat(elapsed)
            guard velocity < Self.hapticVelocityCeiling else {
                lastHapticStep = Int((value / Self.hapticQuantum).rounded())
                return
            }
        }

        let step = Int((value / Self.hapticQuantum).rounded())
        guard step != lastHapticStep else { return }
        lastHapticStep = step
        feedback?.selection()
    }
}
