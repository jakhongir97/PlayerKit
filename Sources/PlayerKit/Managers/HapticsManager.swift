import UIKit

class HapticsManager {
    static let shared = HapticsManager()

    private init() {}

    /// Triggers a haptic feedback of type `impact`.
    /// - Parameter style: The style of impact (light, medium, heavy, soft, rigid).
    func triggerImpactFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Triggers a haptic feedback of type `notification`.
    /// - Parameter type: The type of notification (success, warning, error).
    func triggerNotificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    /// Triggers a haptic feedback of type `selection`.
    func triggerSelectionFeedback() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
