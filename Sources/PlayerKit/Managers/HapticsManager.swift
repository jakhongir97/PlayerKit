#if canImport(UIKit)
import UIKit
public typealias PKImpactFeedbackStyle = UIImpactFeedbackGenerator.FeedbackStyle
public typealias PKNotificationFeedbackType = UINotificationFeedbackGenerator.FeedbackType
#else
import Foundation

public enum PKImpactFeedbackStyle {
    case light
    case medium
    case heavy
    case soft
    case rigid
}

public enum PKNotificationFeedbackType {
    case success
    case warning
    case error
}
#endif

class HapticsManager {
    static let shared = HapticsManager()

    private init() {}

    func triggerImpactFeedback(style: PKImpactFeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    func triggerNotificationFeedback(type: PKNotificationFeedbackType) {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
        #endif
    }

    func triggerSelectionFeedback() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}
