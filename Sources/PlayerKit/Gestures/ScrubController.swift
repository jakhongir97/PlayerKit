import CoreGraphics
import Foundation

/// How much a point of horizontal travel is worth right now.
///
/// Dragging *away* from the scrub axis slows it down, the same affordance the
/// system music and video scrubbers use. It is what makes a 90-minute film
/// placeable to the second without a separate "precision mode" control.
enum ScrubRateTier: Equatable, CaseIterable {
    case hiSpeed
    case half
    case quarter
    case fine

    var rate: Double {
        switch self {
        case .hiSpeed: return 1.0
        case .half: return 0.5
        case .quarter: return 0.25
        case .fine: return 0.1
        }
    }

    /// `nil` at full rate — a label there would be noise, since it is the
    /// state the user is already in.
    var label: String? {
        switch self {
        case .hiSpeed: return nil
        case .half: return "Half-Speed Scrubbing"
        case .quarter: return "Quarter-Speed Scrubbing"
        case .fine: return "Fine Scrubbing"
        }
    }

    static func tier(forVerticalDistance distance: CGFloat) -> ScrubRateTier {
        let d = abs(distance)
        if d >= 150 { return .fine }
        if d >= 100 { return .quarter }
        if d >= 50 { return .half }
        return .hiSpeed
    }
}

/// Horizontal drag to scrub.
///
/// The offset is *integrated* from per-event deltas rather than recomputed from
/// the total translation. That is deliberate: it means changing tier mid-drag
/// re-rates only the travel that happens afterwards, so the playhead never jumps
/// when the finger drifts across a tier boundary, and dragging back out to full
/// rate converges on the thumb rather than snapping.
@MainActor
final class ScrubController {

    private var offset: Double = 0
    private var lastDx: CGFloat = 0
    private var origin: Double = 0
    private var range: ClosedRange<Double> = 0 ... 0
    private var secondsPerPoint: Double = 1
    private var engagementDy: CGFloat = 0
    private(set) var currentTier: ScrubRateTier = .hiSpeed
    private(set) var isActive = false

    struct ScrubSample: Equatable {
        let target: Double
        let delta: Double
        /// Position within the seekable range, 0…1, for the mini-timeline.
        let unit: Double
        let tier: ScrubRateTier
        let didChangeTier: Bool
    }

    func begin(
        from currentTime: Double,
        range: ClosedRange<Double>,
        secondsPerPoint: Double,
        engagementTranslation: CGSize
    ) {
        self.origin = min(max(currentTime, range.lowerBound), range.upperBound)
        self.range = range
        self.secondsPerPoint = secondsPerPoint
        self.offset = 0
        self.lastDx = engagementTranslation.width
        self.engagementDy = engagementTranslation.height
        self.currentTier = .hiSpeed
        self.isActive = true
    }

    func update(
        translation: CGSize,
        feedback: GestureFeedbackPerforming?,
        hapticsEnabled: Bool
    ) -> ScrubSample {
        let dx = translation.width
        let step = Double(dx - lastDx)
        lastDx = dx

        // Tier is read from how far the finger has strayed from where the drag
        // engaged, not from the raw y — otherwise starting a scrub near the top
        // of the screen would begin in fine mode.
        let newTier = ScrubRateTier.tier(forVerticalDistance: translation.height - engagementDy)
        let didChangeTier = newTier != currentTier
        if didChangeTier {
            currentTier = newTier
            if hapticsEnabled { feedback?.selection() }
        }

        offset += step * secondsPerPoint * currentTier.rate

        let target = min(max(origin + offset, range.lowerBound), range.upperBound)
        // Fold the clamp back into the offset so pushing past the end and
        // dragging back does not have to unwind dead travel first.
        offset = target - origin

        let span = range.upperBound - range.lowerBound
        let unit = span > 0 ? (target - range.lowerBound) / span : 0

        return ScrubSample(
            target: target,
            delta: target - origin,
            unit: unit,
            tier: currentTier,
            didChangeTier: didChangeTier
        )
    }

    func commitTarget() -> Double {
        min(max(origin + offset, range.lowerBound), range.upperBound)
    }

    func cancel() {
        isActive = false
        offset = 0
        lastDx = 0
        currentTier = .hiSpeed
    }

    func end() {
        isActive = false
    }
}
