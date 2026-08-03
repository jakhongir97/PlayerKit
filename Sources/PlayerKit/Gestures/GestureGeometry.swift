import CoreGraphics
import SwiftUI

// MARK: - Zones

/// Which half of the picture a vertical rail gesture belongs to.
///
/// Deliberately expressed as leading/trailing rather than left/right: the rails
/// follow the layout direction, so the brightness rail sits under the thumb that
/// naturally reaches it in an RTL locale too.
public enum RailSide: Hashable, Sendable, CaseIterable {
    case leading
    case trailing
}

/// Where a tap landed horizontally.
///
/// This partition is unchanged from the original `GestureManager`, and must stay
/// that way: `DoubleTapSeekOverlayView.tapRingRadius(forWidth:)` is sized so the
/// ring cannot reach across the midline *from the innermost point a seek tap can
/// land on*, and `DoubleTapSeekGestureTests.testTapRingCannotReachAcrossTheMidline`
/// derives that point from `sideZoneWidthRatio`. Changing the ratio without
/// re-deriving the radius silently voids the contract that lets the ring draw
/// with no clip.
enum TapZone: Equatable {
    case backward
    case forward
    /// The middle band, where a double tap deliberately does *not* seek.
    case center

    var seekDirection: SeekDirection? {
        switch self {
        case .backward: return .backward
        case .forward: return .forward
        case .center: return nil
        }
    }
}

/// The vocabulary of things a gesture can drive. Not every kind is reachable by
/// touch on every platform — see `GestureCapabilities`.
enum GestureKind: Hashable {
    case volume
    case brightness
    case scrub
    case speed
    case skip
    case zoom
    case playPause
}

// MARK: - Availability

/// Why a gesture cannot be performed right now.
///
/// Carried rather than collapsed to a bool so the UI can say *something* useful
/// instead of silently swallowing the touch — the failure mode this whole rework
/// exists to remove.
public enum GestureUnavailableReason: Equatable, Sendable {
    case notSupportedOnPlatform
    case externalDisplay
    case noSystemVolumeControl
    case noBackend
    case notSeekable
    case notPlaying
    case disabledByHost
}

public enum GestureAvailability: Equatable, Sendable {
    case available
    case unavailable(GestureUnavailableReason)

    public var isAvailable: Bool { self == .available }

    var unavailableReason: GestureUnavailableReason? {
        switch self {
        case .available: return nil
        case .unavailable(let reason): return reason
        }
    }
}

/// What the current platform, backend and host configuration actually allow.
///
/// The classifier consults this *before* claiming a touch. A gesture whose
/// capability is unavailable never captures the touch at all, so the touch falls
/// through and resolves as a tap — which is what stops a trackpad drift on macOS
/// from vanishing into a brightness gesture that cannot write anything.
struct GestureCapabilities: Equatable {
    var volume: GestureAvailability = .available
    var brightness: GestureAvailability = .available
    var scrub: GestureAvailability = .available
    var speedHold: GestureAvailability = .available
    var zoom: GestureAvailability = .available
    /// False for a pointer-driven surface (macOS, or an iPad trackpad session),
    /// which suppresses the coached walkthrough: there is no swipe to teach.
    var usesTouch: Bool = true

    static let none = GestureCapabilities(
        volume: .unavailable(.disabledByHost),
        brightness: .unavailable(.disabledByHost),
        scrub: .unavailable(.disabledByHost),
        speedHold: .unavailable(.disabledByHost),
        zoom: .unavailable(.disabledByHost),
        usesTouch: true
    )

    func availability(of kind: GestureKind) -> GestureAvailability {
        switch kind {
        case .volume: return volume
        case .brightness: return brightness
        case .scrub: return scrub
        case .speed: return speedHold
        case .zoom: return zoom
        case .skip, .playPause: return .available
        }
    }
}

// MARK: - Surface

/// The drawable area and what the system has already claimed of it.
struct SurfaceGeometry: Equatable {
    var size: CGSize = .zero
    var insets: EdgeInsets = EdgeInsets()
    var layoutDirection: LayoutDirection = .leftToRight

    init(
        size: CGSize = .zero,
        insets: EdgeInsets = EdgeInsets(),
        layoutDirection: LayoutDirection = .leftToRight
    ) {
        self.size = size
        self.insets = insets
        self.layoutDirection = layoutDirection
    }
}

// MARK: - Geometry

/// The single answer to "where am I".
///
/// The classifier, the HUD, the resting affordance and the coach all read this
/// one value. That is the point: the previous code carried *two* disagreeing
/// partitions — taps split 0.4/0.2/0.4 while swipes split 0.33/0.34/0.33 — so
/// between x=0.33w and x=0.40w a touch was "backward" to a tap and "centre" to a
/// swipe. A coach mark drawn from one model could advertise a region the router
/// did not honour. There is now one model and the halves nest inside the thirds.
struct GestureGeometry: Equatable {

    // MARK: Static partition

    /// Fraction of the width in the middle where a double tap does not seek.
    ///
    /// Without it, a quick double tap aimed at showing and hiding the controls
    /// lands on one side or the other and skips by accident.
    static let centerDeadZoneRatio: CGFloat = 0.2

    /// How far in from either edge a seek tap can land, as a fraction of the
    /// width. The overlay sizes its tap ring against this so the ring never
    /// reaches across the midline.
    static var sideZoneWidthRatio: CGFloat { (1 - centerDeadZoneRatio) / 2 }

    /// Vertical inset for the region a *pan* may begin in.
    ///
    /// `preferredScreenEdgesDeferringSystemGestures` only defers the system edge
    /// gesture — the first swipe is lost either way — so the region is inset
    /// rather than fought for. Taps are never inset.
    static let minimumEdgeInset: CGFloat = 24
    static let horizontalEdgeInset: CGFloat = 16

    // MARK: Stored

    var surface: SurfaceGeometry
    var capabilities: GestureCapabilities
    var railMapping: RailMapping

    init(
        surface: SurfaceGeometry = SurfaceGeometry(),
        capabilities: GestureCapabilities = GestureCapabilities(),
        railMapping: RailMapping = .brightnessLeading
    ) {
        self.surface = surface
        self.capabilities = capabilities
        self.railMapping = railMapping
    }

    // MARK: Derived

    var size: CGSize { surface.size }

    /// A zero-width surface is not a surface. Every query degrades to a safe
    /// answer rather than dividing by zero — the previous code guarded this in
    /// one place only.
    var isUsable: Bool { surface.size.width > 0 && surface.size.height > 0 }

    /// Derived from the *view's own* aspect, not `UIDevice.current.orientation`,
    /// so it stays correct in Split View, Slide Over, Stage Manager and on a
    /// second display.
    var isPortraitSurface: Bool { surface.size.width < surface.size.height }

    /// Where a pan may *begin*. Taps are accepted anywhere.
    var activeRect: CGRect {
        guard isUsable else { return .zero }
        let top = max(surface.insets.top, Self.minimumEdgeInset)
        let bottom = max(surface.insets.bottom, Self.minimumEdgeInset)
        let leading = max(surface.insets.leading, Self.horizontalEdgeInset)
        let trailing = max(surface.insets.trailing, Self.horizontalEdgeInset)
        let width = max(surface.size.width - leading - trailing, 0)
        let height = max(surface.size.height - top - bottom, 0)
        return CGRect(x: leading, y: top, width: width, height: height)
    }

    func isPanEligible(_ point: CGPoint) -> Bool {
        guard isUsable else { return false }
        return activeRect.contains(point)
    }

    // MARK: Tap partition

    func tapZone(for point: CGPoint) -> TapZone {
        guard isUsable else { return .center }
        let sideWidthRatio = Self.sideZoneWidthRatio
        let ratio = point.x / surface.size.width
        if ratio < sideWidthRatio { return .backward }
        if ratio > 1 - sideWidthRatio { return .forward }
        return .center
    }

    // MARK: Rail partition

    /// The 50/50 split. Strictly coarser than the tap partition, so no x is ever
    /// "backward" to a tap and "trailing" to a rail.
    func railSide(for point: CGPoint) -> RailSide? {
        guard isUsable else { return nil }
        let physicalSide: RailSide = point.x < surface.size.width / 2 ? .leading : .trailing
        guard surface.layoutDirection == .rightToLeft else { return physicalSide }
        return physicalSide == .leading ? .trailing : .leading
    }

    /// What a rail on this side drives, honouring both the host's mapping and
    /// what the platform can actually do.
    ///
    /// When brightness is unavailable, *both* halves drive volume rather than
    /// leaving half the screen inert. That is the macOS story, and it is why the
    /// coach shows one lesson there instead of two.
    func kind(forSide side: RailSide) -> GestureKind? {
        let brightnessSide: RailSide = railMapping == .brightnessLeading ? .leading : .trailing
        let nominal: GestureKind = side == brightnessSide ? .brightness : .volume

        if capabilities.availability(of: nominal).isAvailable { return nominal }

        let other: GestureKind = nominal == .brightness ? .volume : .brightness
        if capabilities.availability(of: other).isAvailable { return other }

        return nil
    }

    // MARK: Magnitudes

    /// How far a finger travels to sweep a rail end to end.
    ///
    /// Half the usable height, floored and capped so a short landscape phone is
    /// not twitchy and a tall iPad is not exhausting. The previous code used a
    /// fixed sensitivity of 0.01 per point — 100pt for the full range, about a
    /// quarter of a landscape phone's height, which is why a small nudge threw
    /// the volume across the room.
    var fullRangeTravel: CGFloat {
        guard isUsable else { return 200 }
        return min(max(0.5 * activeRect.height, 160), 260)
    }

    /// Seconds of media per point of horizontal travel.
    ///
    /// Scaled to the media's own length so a 90-minute film and a 3-minute clip
    /// both cross in roughly the same swipe, then floored so a very short clip
    /// does not become impossible to place.
    func secondsPerPoint(span: Double) -> Double {
        let width = activeRect.width
        guard width > 0 else { return 1 }
        let clamped = min(max(span, 60), 2400)
        return max(clamped / (0.8 * Double(width)), 0.05)
    }

    // MARK: Frames

    /// Where the rail draws. The live HUD, the resting affordance and the coach
    /// all call this, so a coach mark cannot point somewhere the rail is not.
    func railFrame(_ side: RailSide) -> CGRect {
        guard isUsable else { return .zero }
        let height = min(0.46 * surface.size.height, 180)
        let width: CGFloat = 6
        let inset: CGFloat
        let physicalSide: RailSide
        if surface.layoutDirection == .rightToLeft {
            physicalSide = side == .leading ? .trailing : .leading
        } else {
            physicalSide = side
        }
        switch physicalSide {
        case .leading:
            inset = max(surface.insets.leading, 20)
            return CGRect(
                x: inset,
                y: (surface.size.height - height) / 2,
                width: width,
                height: height
            )
        case .trailing:
            inset = max(surface.insets.trailing, 20)
            return CGRect(
                x: surface.size.width - inset - width,
                y: (surface.size.height - height) / 2,
                width: width,
                height: height
            )
        }
    }

    /// Converts a point into 0…1 of the surface.
    ///
    /// The seek overlay stores its origin this way so rotating mid-session
    /// cannot strand the tap ring off-screen — the previous code stored raw
    /// points captured against the pre-rotation size.
    func unitPoint(_ point: CGPoint) -> CGPoint {
        guard isUsable else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: min(max(point.x / surface.size.width, 0), 1),
            y: min(max(point.y / surface.size.height, 0), 1)
        )
    }

    func point(fromUnit unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }
}
