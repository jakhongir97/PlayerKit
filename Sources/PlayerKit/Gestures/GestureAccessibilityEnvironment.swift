@preconcurrency import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Which assistive technologies are running.
///
/// Nothing in the package could previously branch on this at the model layer,
/// which is why the gesture surface had no accessible equivalent for any of its
/// gestures. Reading it as a value — rather than at each call site — keeps the
/// whole suppression matrix table-testable.
struct AssistiveTechnologyState: Equatable {
    var isVoiceOverRunning = false
    var isSwitchControlRunning = false
    var isVoiceControlRunning = false
    var isGuidedAccessEnabled = false
    var isAssistiveTouchRunning = false
    var reduceMotion = false

    /// Chrome that disappears on a timer is unusable when navigating by focus.
    var suppressesAutoHide: Bool {
        isVoiceOverRunning
            || isSwitchControlRunning
            || isVoiceControlRunning
            || isGuidedAccessEnabled
    }

    /// Teaching a swipe to someone who cannot emit one steals focus and teaches
    /// nothing. They get the named actions and the visible ±10s buttons instead —
    /// the accessible equivalent, not a consolation prize.
    var suppressesCoach: Bool {
        isVoiceOverRunning || isSwitchControlRunning || isVoiceControlRunning
    }

    /// A 0.28s double-tap window is not reachable through Switch Control or
    /// AssistiveTouch.
    var needsRelaxedTiming: Bool {
        isSwitchControlRunning || isAssistiveTouchRunning
    }

    @MainActor
    static var current: AssistiveTechnologyState {
        #if canImport(UIKit)
        return AssistiveTechnologyState(
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            isSwitchControlRunning: UIAccessibility.isSwitchControlRunning,
            // UIKit exposes running-state APIs for VoiceOver and Switch
            // Control, but not Voice Control. GestureManager can merge an
            // explicit host-provided override without using private API.
            isVoiceControlRunning: false,
            isGuidedAccessEnabled: UIAccessibility.isGuidedAccessEnabled,
            isAssistiveTouchRunning: UIAccessibility.isAssistiveTouchRunning,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        #elseif canImport(AppKit)
        return AssistiveTechnologyState(
            isVoiceOverRunning: NSWorkspace.shared.isVoiceOverEnabled,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        #else
        return AssistiveTechnologyState()
        #endif
    }
}

/// Keeps an `AssistiveTechnologyState` current.
@MainActor
final class AssistiveTechnologyObserver {
    private(set) var state: AssistiveTechnologyState = .current
    var onChange: ((AssistiveTechnologyState) -> Void)?

    private var observers: [NSObjectProtocol] = []
    #if canImport(AppKit)
    private var voiceOverObservation: NSKeyValueObservation?
    #endif

    init() {
        #if canImport(UIKit)
        let names: [Notification.Name] = [
            UIAccessibility.voiceOverStatusDidChangeNotification,
            UIAccessibility.switchControlStatusDidChangeNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.assistiveTouchStatusDidChangeNotification,
            UIAccessibility.guidedAccessStatusDidChangeNotification
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
        #elseif canImport(AppKit)
        voiceOverObservation = NSWorkspace.shared.observe(
            \.isVoiceOverEnabled,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        ]
        #endif
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        #if canImport(AppKit)
        voiceOverObservation?.invalidate()
        #endif
    }

    private func refresh() {
        let next = AssistiveTechnologyState.current
        guard next != state else { return }
        state = next
        onChange?(next)
    }
}

/// Announcements from the **model**, not from an overlay that vanishes in 0.7s.
///
/// A HUD that is `accessibilityHidden` still has to tell VoiceOver what it
/// changed; announcing from here is what makes a rail usable without sight.
@MainActor
enum GestureAnnouncer {
    static func announce(_ text: String, state: AssistiveTechnologyState) {
        guard state.isVoiceOverRunning else { return }
        #if canImport(UIKit)
        // Keep one implementation across PlayerKit's full iOS range. The
        // newer AttributedString announcement API currently emits a strict-
        // concurrency KeyPath warning in device builds.
        let attributed = NSAttributedString(
            string: text,
            attributes: [.accessibilitySpeechQueueAnnouncement: false]
        )
        UIAccessibility.post(notification: .announcement, argument: attributed)
        #elseif canImport(AppKit)
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
        #endif
    }
}

#if canImport(UIKit)
import SwiftUI
#endif
