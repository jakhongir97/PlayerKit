import CoreGraphics
import Foundation

enum AdjustDirection: Equatable {
    case increment
    case decrement
}

/// Whether a controls toggle happens now or waits to see if a second tap lands.
///
/// The deferral exists because of a specific, visible glitch: a single tap
/// showed the whole chrome — top bar, transport row, and a 50% black scrim over
/// the picture — with a 0.3s fade, and the second tap of a double tap has to
/// arrive inside 0.28s, i.e. always *during* that fade. So every skip was
/// preceded by the entire interface washing in and straight back out. Only the
/// *show* needs holding back; hiding stays immediate, because a user who taps to
/// dismiss the chrome should never wait for it.
enum TogglePolicy: Equatable {
    case immediate
    case deferredUntilDoubleTapWindowCloses
}

/// The router's entire vocabulary.
///
/// `Equatable` so a test can assert an exact sequence rather than poking at
/// internal state, and every payload is small enough that emitting one never
/// boxes onto the heap — this type is constructed on the touch path.
enum GestureIntent: Equatable {

    // MARK: Controls and transport

    case toggleControls(TogglePolicy)
    case setControlsVisible(Bool)
    case togglePlayback

    // MARK: Skip

    case skipOverlay(DoubleTapSeekOverlayState?)
    case seek(to: Double)
    case seekSession(isOpen: Bool)

    // MARK: Rails

    /// Tier 1. The rail has been revealed under a resting finger; nothing has
    /// been written and lifting now is an ordinary tap.
    case levelArmed(GestureKind, RailSide)
    case levelBegan(GestureKind, RailSide)
    /// Already quantised and deduplicated upstream, so a subscriber may treat
    /// every one of these as a real change.
    case levelChanged(GestureKind, unit: Double)
    case levelPinned(GestureKind, atMaximum: Bool)
    case levelEnded(GestureKind)

    // MARK: Scrub

    case scrubBegan
    case scrubChanged(offsetSeconds: Double, tier: ScrubRateTier)
    /// `nil` means the scrub was cancelled and **no** seek should be issued.
    case scrubEnded(committedTarget: Double?)

    // MARK: Other gestures

    case speedHoldBegan
    case speedHoldEnded
    case zoom(fill: Bool)

    // MARK: Signals

    case axisLocked
    /// A gesture was attempted that the lock forbids. Emitted rather than
    /// swallowed: silence is indistinguishable from a broken player.
    case blocked(GestureKind)
    /// The user engaged a rail axis and then gave up almost immediately.
    case abandonedAdjustAttempt(GestureKind, RailSide)
    /// Repeated taps in one half by someone who has never once swiped there.
    case repeatedTapWithoutSwipe(RailSide)
    case cancel
}
