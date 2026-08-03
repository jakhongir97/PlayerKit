import Foundation

/// One value describing everything the feedback layer is showing.
///
/// Deliberately a single vocabulary for every gesture — volume, brightness,
/// scrub, speed, zoom, play/pause and "this is locked" all produce one of these.
/// That is the learnability argument made structural: the shapes, the motion and
/// the placement rhyme, so understanding one gesture's feedback teaches the
/// shape of all of them.
struct GestureHUD: Equatable {

    enum Kind: Equatable {
        case volume
        case brightness
        case scrub
        case speed
        case zoom
        case playPause
        case blocked
    }

    /// Where it draws. The rail slots are anchored to `GestureGeometry.railFrame`,
    /// which is the same frame the resting affordance and the coach use, so a
    /// hint can never point somewhere the rail is not.
    enum Slot: Equatable {
        case rail(RailSide)
        case banner
        case center
    }

    var kind: Kind
    var slot: Slot
    /// SF Symbol name. A string literal in every case, so building one of these
    /// on the touch path does not allocate.
    var symbol: String
    /// "62%" | "12:04" | "2×" | "Fill" | "Locked"
    var primary: String
    /// "+2:41" | "Half-Speed Scrubbing" | "Device volume is low"
    var secondary: String?
    /// "12:04 → 14:45"
    var tertiary: String?
    /// 0…1 draws the rail; `nil` draws no rail.
    var fraction: Double?
    var isPinned: Bool = false
    /// Tier 1: revealed under a resting finger, nothing written yet. Drawn at
    /// reduced opacity so "I can see it" and "I have changed it" never look the
    /// same.
    var isArmed: Bool = false
    /// Driven by the coach rather than by a finger.
    var isDemo: Bool = false
    /// Bumped to replay a one-shot animation without changing view identity.
    var pulse: Int = 0

    var accessibilityAnnouncement: String {
        accessibilityAnnouncement(using: PlayerStrings())
    }

    func accessibilityAnnouncement(using strings: PlayerStrings) -> String {
        switch kind {
        case .volume: return strings.volumeAnnouncement(primary)
        case .brightness: return strings.brightnessAnnouncement(primary)
        case .scrub: return strings.scrubAnnouncement(primary, secondary)
        case .speed: return strings.playbackSpeedAnnouncement(primary)
        case .zoom, .playPause: return primary
        case .blocked: return strings.controlsAreLocked
        }
    }
}
