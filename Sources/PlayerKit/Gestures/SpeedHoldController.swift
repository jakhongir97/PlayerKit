import Foundation

/// Press and hold to run at double speed, release to go back.
///
/// The previous speed is captured on engage and restored on release *and* on
/// cancellation, because the cancel path is the one that actually matters: if a
/// call banner steals the touch while the finger is down, a player left running
/// at 2× with no visible reason is worse than one that never had the gesture.
@MainActor
final class SpeedHoldController {

    var multiplier: Float = 2.0
    var ceiling: Float = 4.0

    var speedProvider: (() -> Float)?
    var onSetSpeed: ((Float) -> Void)?
    /// `isPlaying && !isLocked && no seek session open`.
    var canEngage: (() -> Bool)?

    private var previousSpeed: Float?

    var isEngaged: Bool { previousSpeed != nil }
    var engagedSpeed: Float {
        min((previousSpeed ?? 1) * multiplier, ceiling)
    }

    @discardableResult
    func engage(feedback: GestureFeedbackPerforming?, hapticsEnabled: Bool) -> Bool {
        guard previousSpeed == nil else { return false }
        guard canEngage?() ?? true else { return false }
        let current = speedProvider?() ?? 1
        previousSpeed = current
        onSetSpeed?(min(current * multiplier, ceiling))
        if hapticsEnabled { feedback?.impact(.medium) }
        return true
    }

    /// Idempotent, and also the cancel path.
    @discardableResult
    func release(feedback: GestureFeedbackPerforming?, hapticsEnabled: Bool) -> Bool {
        guard let previous = previousSpeed else { return false }
        previousSpeed = nil
        onSetSpeed?(previous)
        if hapticsEnabled { feedback?.impact(.light) }
        return true
    }
}
