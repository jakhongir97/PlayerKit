import CoreGraphics
import Foundation

/// What put the events on the wire. A trackpad or mouse is far more precise than
/// a fingertip, so it gets a much tighter slop.
enum PointerSource: Equatable {
    case touch
    case pointer
}

/// The one thing a touch can turn out to be.
///
/// Resolved exactly once, at the slop threshold, and then owned to completion.
/// The previous implementation re-derived this on every drag event from a
/// `@State private var isPanning`, which could survive a cancelled sequence and
/// mis-classify the next one.
enum TouchOutcome: Equatable {
    case undecided
    case tap
    case verticalRail(RailSide)
    case horizontalScrub
    case speedHold
    /// The user clearly meant a gesture that this platform, backend or
    /// configuration cannot perform. Terminal, and resolves as a tap on lift —
    /// see the fall-through rule. Carrying the reason is what lets the UI say so
    /// instead of eating the touch.
    case inert(GestureUnavailableReason)

    var isResolved: Bool { self != .undecided }
}

enum GestureAxis: Equatable {
    case undecided
    case vertical
    case horizontal
}

/// Everything the classifier needs to know about the world, passed in rather
/// than reached for, so the type stays free of every platform import.
struct ClassificationContext {
    var railAvailability: (RailSide) -> GestureAvailability = { _ in .available }
    var isScrubAvailable: Bool = true
    var startSide: RailSide?
    var isPanEligible: Bool = true
}

/// One touch, one outcome.
///
/// Deliberately free of SwiftUI, UIKit and AppKit: the whole classification
/// matrix — zone × axis × capability × source — is a pure function of values,
/// and therefore assertable in a unit test with no host application.
final class TouchClassifier {

    struct Tuning: Equatable {
        /// How far a fingertip may drift and still be a tap.
        var touchSlop: CGFloat = 10
        /// A trackpad or mouse does not tremble.
        var pointerSlop: CGFloat = 3
        /// An *unresolved* touch that lifts inside this is still a tap. Rescues
        /// a hand tremor that crossed the slop but never committed to an axis.
        var sloppyTapLimit: CGFloat = 24
        /// How dominant one axis must be before it is claimed. The ±33.7° band
        /// either side of the diagonal is deliberately left unclaimed rather
        /// than arbitrarily assigned.
        var axisRatio: CGFloat = 1.5
        var holdDuration: TimeInterval = 0.45
        var holdMovement: CGFloat = 10
        /// A tap resolves well inside this, so a plain tap never arms a rail;
        /// a finger that lingers is already probing.
        var armDelay: TimeInterval = 0.12
        var twoFingerTapWindow: TimeInterval = 0.30

        func slop(for source: PointerSource) -> CGFloat {
            source == .pointer ? pointerSlop : touchSlop
        }
    }

    private(set) var outcome: TouchOutcome = .undecided
    private(set) var axis: GestureAxis = .undecided
    private(set) var startLocation: CGPoint = .zero
    /// The translation at the moment the axis was claimed.
    ///
    /// Subtracting it is what removes the lurch the old code produced: it fed
    /// the *total* translation into the level, so the value jumped by a full
    /// slop's worth the instant the gesture engaged.
    private(set) var engagementTranslation: CGSize = .zero
    private(set) var isActive = false
    private(set) var isArmed = false
    private(set) var maxTouchCount = 0
    private(set) var startTime: TimeInterval = 0
    private(set) var lastTranslation: CGSize = .zero

    private var tuning = Tuning()
    private var source: PointerSource = .touch
    private var didFinish = false

    var travel: CGFloat {
        hypot(lastTranslation.width, lastTranslation.height)
    }

    // MARK: - Lifecycle

    func begin(at location: CGPoint, touchCount: Int, now: TimeInterval, tuning: Tuning, source: PointerSource) {
        self.tuning = tuning
        self.source = source
        outcome = .undecided
        axis = .undecided
        startLocation = location
        engagementTranslation = .zero
        lastTranslation = .zero
        isActive = true
        isArmed = false
        didFinish = false
        maxTouchCount = touchCount
        startTime = now
    }

    /// Returns `true` when the outcome changed on this event, so the caller only
    /// does work on a transition.
    @discardableResult
    func update(translation: CGSize, touchCount: Int, now: TimeInterval, context: ClassificationContext) -> Bool {
        guard isActive else { return false }
        lastTranslation = translation
        maxTouchCount = max(maxTouchCount, touchCount)

        // Once resolved, a touch is never re-classified. A finger that commits
        // to volume and then wanders sideways keeps adjusting volume.
        guard !outcome.isResolved else { return false }

        let slop = tuning.slop(for: source)
        let dx = translation.width
        let dy = translation.height
        guard hypot(dx, dy) > slop else { return false }

        let adx = abs(dx)
        let ady = abs(dy)

        if ady >= tuning.axisRatio * adx {
            axis = .vertical
            return resolveVertical(context: context, translation: translation)
        }

        if adx >= tuning.axisRatio * ady {
            axis = .horizontal
            return resolveHorizontal(context: context, translation: translation)
        }

        // In the unclaimed diagonal band. Keep sampling — the finger usually
        // commits within another few points.
        return false
    }

    private func resolveVertical(context: ClassificationContext, translation: CGSize) -> Bool {
        guard context.isPanEligible, let side = context.startSide else {
            // Began on a system edge, or on a surface with no usable geometry.
            // Claim nothing; the touch will fall through and resolve as a tap.
            return false
        }
        let availability = context.railAvailability(side)
        switch availability {
        case .available:
            outcome = .verticalRail(side)
        case .unavailable(let reason):
            outcome = .inert(reason)
        }
        engagementTranslation = translation
        return true
    }

    private func resolveHorizontal(context: ClassificationContext, translation: CGSize) -> Bool {
        guard context.isPanEligible else { return false }
        guard context.isScrubAvailable else {
            outcome = .inert(.notSeekable)
            engagementTranslation = translation
            return true
        }
        outcome = .horizontalScrub
        engagementTranslation = translation
        return true
    }

    // MARK: - Promotions

    /// Fired by the arm timer. Reveals the rail under a resting finger without
    /// writing anything.
    func promoteToArmed() -> Bool {
        guard isActive, !outcome.isResolved, !isArmed else { return false }
        guard travel <= tuning.holdMovement else { return false }
        isArmed = true
        return true
    }

    /// Fired by the hold timer. A touch that becomes a hold can never become a
    /// tap, which is what stops a released long-press from also toggling the
    /// controls.
    func promoteToHold() -> Bool {
        guard isActive, !outcome.isResolved else { return false }
        guard travel < tuning.holdMovement else { return false }
        outcome = .speedHold
        return true
    }

    /// Records that a second finger landed. A pinch must never also be a tap or
    /// ride a rail, so the drag path is abandoned outright.
    func noteAdditionalTouch(count: Int) {
        maxTouchCount = max(maxTouchCount, count)
    }

    // MARK: - Finish

    /// **Idempotent** — a second call returns `nil`.
    ///
    /// UIKit can deliver `touchesEnded` and `touchesCancelled` for different
    /// touches of the same sequence, so the ordering between the two paths has
    /// to stop mattering.
    func finish(cancelled: Bool) -> TouchOutcome? {
        guard isActive, !didFinish else { return nil }
        didFinish = true
        isActive = false

        if cancelled {
            return .undecided
        }

        if outcome.isResolved {
            return outcome
        }

        // Never resolved an axis. A short enough lift is still a tap.
        if travel < tuning.sloppyTapLimit, maxTouchCount <= 1 {
            outcome = .tap
            return .tap
        }

        return .undecided
    }
}
