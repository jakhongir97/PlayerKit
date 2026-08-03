import Foundation

/// Haptic feedback, behind a seam.
///
/// The gesture controllers fire haptics on paths that are otherwise pure value
/// transforms, so the seam is what lets a test assert "one selection tick per
/// 1/16 step, suppressed above 600 pt/s" without a device in the room.
@MainActor
protocol GestureFeedbackPerforming: AnyObject {
    func prepare(_ style: PKImpactFeedbackStyle)
    func impact(_ style: PKImpactFeedbackStyle)
    func selection()
    func notification(_ type: PKNotificationFeedbackType)
}

/// Adapts the existing pooled generators. No behaviour change — the pooling and
/// the re-arm that `HapticsManager` already does are exactly what a rapid rail
/// sweep needs.
extension HapticsManager: GestureFeedbackPerforming {
    func prepare(_ style: PKImpactFeedbackStyle) {
        prepareImpactFeedback(style: style)
    }

    func impact(_ style: PKImpactFeedbackStyle) {
        triggerImpactFeedback(style: style)
    }

    func selection() {
        triggerSelectionFeedback()
    }

    func notification(_ type: PKNotificationFeedbackType) {
        triggerNotificationFeedback(type: type)
    }
}

enum HapticEvent: Equatable {
    case prepare(PKImpactFeedbackStyle)
    case impact(PKImpactFeedbackStyle)
    case selection
    case notification(PKNotificationFeedbackType)
}

/// Test double.
@MainActor
final class RecordingFeedback: GestureFeedbackPerforming {
    private(set) var events: [HapticEvent] = []

    func prepare(_ style: PKImpactFeedbackStyle) { events.append(.prepare(style)) }
    func impact(_ style: PKImpactFeedbackStyle) { events.append(.impact(style)) }
    func selection() { events.append(.selection) }
    func notification(_ type: PKNotificationFeedbackType) { events.append(.notification(type)) }

    func reset() { events.removeAll() }

    var impacts: [PKImpactFeedbackStyle] {
        events.compactMap {
            if case .impact(let style) = $0 { return style }
            return nil
        }
    }

    var selectionCount: Int {
        events.filter { $0 == .selection }.count
    }
}
