import Foundation

/// What the gesture layer can currently do, given the platform, the display and
/// the loaded backend.
///
/// Exposed so a host can hide an affordance rather than offering a control that
/// silently does nothing — the failure mode this whole rework exists to remove.
public struct PublicGestureCapabilities: Equatable, Sendable {
    public let volume: GestureAvailability
    public let brightness: GestureAvailability
    /// True when the brightness gesture changes the device's own panel, rather
    /// than only compositing a scrim over the video.
    public let brightnessIsSystemWide: Bool
    public let scrub: GestureAvailability
    public let speedHold: GestureAvailability
    public let zoom: GestureAvailability
    /// False on a pointer-driven surface, where there is no swipe to teach.
    public let usesTouch: Bool
}

public enum GestureAdjustmentDirection: Sendable {
    case increment
    case decrement

    var internalDirection: AdjustDirection {
        self == .increment ? .increment : .decrement
    }
}

public extension Notification.Name {
    /// Posted when the gesture walkthrough finishes, so a host can chain its own
    /// onboarding onto the end of ours.
    static let PlayerKitGestureCoachingDidFinish = Notification.Name("PlayerKitGestureCoachingDidFinish")
}

// MARK: - Public surface

public extension PlayerManager {

    /// Gesture behaviour.
    ///
    /// Assigning takes effect on the next touch; a gesture already in flight
    /// finishes under the rules it started with, so a configuration change can
    /// never strand a rail half-written.
    var gestureConfiguration: GestureConfiguration {
        get { gestureManager.configuration }
        set { gestureManager.configuration = newValue }
    }

    var gestureCapabilities: PublicGestureCapabilities {
        let capabilities = gestureManager.currentCapabilities()
        return PublicGestureCapabilities(
            volume: capabilities.volume,
            brightness: capabilities.brightness,
            brightnessIsSystemWide: gestureManager.brightnessControl.isSystemWide,
            scrub: capabilities.scrub,
            speedHold: capabilities.speedHold,
            zoom: capabilities.zoom,
            usesTouch: capabilities.usesTouch
        )
    }

    /// The **player's** output level, 0…1 — not the device's. The hardware
    /// volume buttons and Control Centre are unaffected.
    var volume: Double {
        get { gestureManager.level(of: .volume) }
        set {
            guard newValue.isFinite else { return }
            gestureManager.setLevel(.volume, newValue)
        }
    }

    /// Replays the first-run gesture walkthrough, ignoring the "already seen"
    /// flag.
    ///
    /// Re-entry is not optional: a tutorial that cannot be summoned again is one
    /// the user is not allowed to re-read. Wire this into your own chrome if you
    /// replace PlayerKit's.
    func showGestureCoach() {
        gestureManager.showGestureCoach()
    }

    func dismissGestureCoach() {
        gestureManager.coach.dismiss(.hostDisabled)
    }

    /// Clears every persisted coaching flag, so the walkthrough behaves as it
    /// does on a fresh install.
    func resetGestureCoach() {
        gestureManager.coach.resetPersistedState()
    }

    // MARK: Location-free intents

    /// A plain ±interval seek — the discrete counterpart to the double-tap
    /// session. It shares the session's clamp and its in-flight anchoring, but
    /// draws no overlay and accumulates no readout: a button does a button's
    /// job, and only the fingertip gesture gets the YouTube-style counter.
    func skipForward() {
        gestureManager.skipForward()
    }

    func skipBackward() {
        gestureManager.skipBackward()
    }

    func nudgeVolume(_ direction: GestureAdjustmentDirection) {
        gestureManager.nudge(.volume, direction.internalDirection)
    }

    func nudgeBrightness(_ direction: GestureAdjustmentDirection) {
        gestureManager.nudge(.brightness, direction.internalDirection)
    }
}
