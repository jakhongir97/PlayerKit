import Foundation

/// Where a volume gesture writes.
public enum VolumeGestureTarget: String, Equatable, Sendable, CaseIterable {
    /// The backend's own output level. The default: it is scoped to this player,
    /// it needs no private-view trickery, and it cannot leave the device quieter
    /// than the user found it.
    case player
    /// The device's ringer-independent playback volume. Opt-in, because it
    /// mounts an `MPVolumeView` and changes a system-wide setting.
    case system
}

/// How a brightness gesture darkens the picture.
public enum PlayerKitBrightnessMode: String, Equatable, Sendable, CaseIterable {
    /// Screen brightness, with a compositing scrim below the hardware floor.
    case screen
    /// Never touch the panel; darken with the scrim only. For hosts that do not
    /// want a player changing a system-wide setting.
    case overlayOnly
    case disabled
}

/// Which half of the picture drives which rail.
public enum RailMapping: String, Equatable, Sendable, CaseIterable {
    /// Brightness leading, volume trailing. Matches VLC for iOS, Infuse and
    /// MX Player, and is the default.
    case brightnessLeading
    /// The inverse. A migration escape hatch: inverting a mapping users have
    /// already learned is itself a UX event, so a host with an installed base
    /// gets one release of cover.
    case volumeLeading
}

/// When the coached walkthrough may appear.
public enum GestureCoachPolicy: String, Equatable, Sendable, CaseIterable {
    /// Once per install, capped at two presentations. The default.
    case firstRun
    /// Every playback. For demos and screenshots.
    case always
    case disabled
}

/// Everything a host can tune about the gesture layer.
///
/// Assigning takes effect on the next touch; a gesture already in flight
/// finishes under the rules it started with, so a configuration change can never
/// strand a rail half-written.
public struct GestureConfiguration: Equatable, Sendable {

    /// Master switch. Note that `false` still leaves single-tap-to-toggle
    /// working — a video surface that does not respond to a tap at all reads as
    /// broken, not as configured.
    public var isEnabled: Bool = true

    public var isVolumeGestureEnabled: Bool = true
    public var volumeTarget: VolumeGestureTarget = .player

    public var brightnessMode: PlayerKitBrightnessMode = .screen
    /// Hand the panel back on teardown. Screen brightness is a system-wide
    /// setting; leaving a device dim after the player closes is a bug the old
    /// code shipped for a while.
    public var restoresBrightnessOnExit: Bool = true

    public var isScrubGestureEnabled: Bool = true

    public var isSpeedHoldEnabled: Bool = true
    public var speedHoldMultiplier: Float = 2.0

    public var isZoomGestureEnabled: Bool = true
    public var isTwoFingerPlayPauseEnabled: Bool = true

    public var isHapticsEnabled: Bool = true

    /// Seconds one double-tap skip covers. Clamped to 1…120 on assignment.
    public var skipInterval: Double = 10 {
        didSet { skipInterval = min(max(skipInterval, 1), 120) }
    }

    public var railMapping: RailMapping = .brightnessLeading

    /// The quiet resting rails drawn while the controls are up (tier 0).
    public var showsRestingRailAffordance: Bool = true
    /// The one-line tip shown after a detectably failed gesture (tier 3).
    public var showsConfusionNudges: Bool = true

    /// How long the HUD lingers after the finger lifts.
    public var hudDwell: TimeInterval = 0.70

    public var coachPolicy: GestureCoachPolicy = .firstRun

    public init() {}
}
