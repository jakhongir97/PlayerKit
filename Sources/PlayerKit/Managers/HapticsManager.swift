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

/// Taptic feedback, with the generators kept alive between hits.
///
/// Every call used to allocate a generator, `prepare()` it and fire in the same
/// breath. `prepare()` is a *request* to spin the Taptic Engine up — it does not
/// block — so firing immediately after it means firing into a cold engine, and
/// the tap the user feels lands late or not at all. Holding the generators lets
/// the engine be warmed ahead of the hit (see `prepareImpactFeedback`) and stops
/// a run of rapid feedback, like a double-tap seek session, allocating one
/// generator per tap.
///
/// Main-thread only: `UIFeedbackGenerator` is a UIKit type. Every caller is a
/// SwiftUI action or a gesture callback, both of which already run there.
@MainActor
class HapticsManager {
    static let shared = HapticsManager()

    #if canImport(UIKit)
    private var impactGenerators: [PKImpactFeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()
    private lazy var selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    private init() {}

    /// Warms the engine for feedback that is about to happen.
    ///
    /// Call this the moment a hit becomes likely — the first tap of a possible
    /// double tap, a finger landing on a control — not when it fires. The engine
    /// stays ready for a short while and settles on its own afterwards.
    func prepareImpactFeedback(style: PKImpactFeedbackStyle) {
        #if canImport(UIKit)
        impactGenerator(for: style).prepare()
        #endif
    }

    func triggerImpactFeedback(style: PKImpactFeedbackStyle) {
        #if canImport(UIKit)
        let generator = impactGenerator(for: style)
        generator.impactOccurred()
        // Re-arm for the next hit in a run. Cheap once the engine is already up,
        // and it keeps the second and later taps of a session as prompt as the
        // first.
        generator.prepare()
        #endif
    }

    func triggerNotificationFeedback(type: PKNotificationFeedbackType) {
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
        #endif
    }

    func triggerSelectionFeedback() {
        #if canImport(UIKit)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }

    #if canImport(UIKit)
    private func impactGenerator(for style: PKImpactFeedbackStyle) -> UIImpactFeedbackGenerator {
        if let existing = impactGenerators[style] { return existing }
        let generator = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        return generator
    }
    #endif
}
