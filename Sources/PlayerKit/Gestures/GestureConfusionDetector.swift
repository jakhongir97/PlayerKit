import CoreGraphics
import Foundation

/// Notices that someone tried a gesture and failed.
///
/// The highest-signal moment in a player is a user who has already shown intent
/// and got nothing back — far better than a first-run overlay, because the
/// person is asking the question right now. Two signals, both cheap:
///
/// - **A**: a vertical pan that engaged an axis and then lifted having barely
///   moved. That is someone probing, not someone adjusting.
/// - **B**: repeated taps in one half by someone who has never once swiped
///   there this session — the "why isn't this doing anything" pattern.
final class GestureConfusionDetector {

    private let abandonedThreshold: CGFloat = 25
    private let repeatedTapCount = 3
    private let repeatedTapWindow: TimeInterval = 6.0

    private var hasEngagedRailThisSession = false
    private var recentTaps: [(side: RailSide, time: TimeInterval)] = []
    private var didNudgeThisSession = false

    func noteAdjustAttempt(kind: GestureKind, side: RailSide, travel: CGFloat) -> GestureIntent? {
        guard !didNudgeThisSession else { return nil }
        guard travel < abandonedThreshold else {
            hasEngagedRailThisSession = true
            return nil
        }
        didNudgeThisSession = true
        return .abandonedAdjustAttempt(kind, side)
    }

    func noteTap(side: RailSide?, now: TimeInterval) -> GestureIntent? {
        guard !didNudgeThisSession, !hasEngagedRailThisSession, let side else { return nil }
        recentTaps.removeAll { now - $0.time > repeatedTapWindow }
        recentTaps.append((side, now))
        let sameSide = recentTaps.filter { $0.side == side }
        guard sameSide.count >= repeatedTapCount else { return nil }
        didNudgeThisSession = true
        recentTaps.removeAll()
        return .repeatedTapWithoutSwipe(side)
    }

    func noteRailEngaged() {
        hasEngagedRailThisSession = true
    }

    /// One nudge per playback session, at most.
    func resetSession() {
        hasEngagedRailThisSession = false
        recentTaps.removeAll()
        didNudgeThisSession = false
    }
}
