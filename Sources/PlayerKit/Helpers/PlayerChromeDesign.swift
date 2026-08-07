import SwiftUI

// MARK: - Host-supplied appearance

/// The one styling hook PlayerKit exposes to its host.
///
/// PlayerKit used to hardcode every colour, so an embedding app could not make
/// the player look like the rest of itself: the skip pill was black, the
/// scrubber was white, and the recovery card was whatever `accentColor` the
/// host's window happened to carry. A single accent covers the three places a
/// brand actually belongs — the primary action pill, the played portion of the
/// scrubber, and the emphasised control — and nothing else, so a host cannot
/// turn the chrome into a rainbow.
///
/// The default is white on black, which is what a player with no brand should
/// look like: neutral, high-contrast, and correct over any frame.
public struct PlayerAppearance: Equatable, Sendable {
    /// Fills the primary action pill and the played portion of the scrubber.
    public var accent: Color
    /// Draws on top of `accent`. Must clear contrast against it.
    public var accentForeground: Color

    public init(accent: Color = .white, accentForeground: Color = .black) {
        self.accent = accent
        self.accentForeground = accentForeground
    }

    public static let `default` = PlayerAppearance()
}

// MARK: - Metrics

/// Every size and gap in the player chrome.
///
/// The chrome previously carried eleven ad-hoc sizes (30, 36, 38, 40, 44, 45,
/// 50, 60, 64 …) and four spacing values chosen per view, which is why the
/// controls read as scattered rather than as one bar. Three control sizes and
/// one 4pt spacing scale is enough to build every row the player needs.
public enum PlayerChromeMetrics {
    // Spacing scale. Nothing in the chrome may invent a gap outside it.
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingM: CGFloat = 12
    public static let spacingL: CGFloat = 16
    public static let spacingXL: CGFloat = 24

    /// The play/pause control. The only control at this size — that is what
    /// makes it read as primary without needing a colour of its own.
    public static var primaryControlDiameter: CGFloat {
        PlayerKitPlatform.isDesktop ? 64 : 60
    }

    /// Skip ±10 and previous/next: everything in the transport that is not
    /// play/pause. They were 44pt bare glyphs and 60pt glass discs in the same
    /// row; one size makes the row a set.
    public static let secondaryControlDiameter: CGFloat = 48

    /// Icon controls that live in a bar or a group — close, lock, info, PiP,
    /// full screen, the menu triggers.
    public static let barControlDiameter: CGFloat = 38

    /// The height every item in the top and bottom bars aligns to, so pills and
    /// icon groups share one baseline instead of four.
    public static let barItemHeight: CGFloat = 44

    /// HIG minimum touch target. Controls smaller than this expand their
    /// content shape rather than their visible surface.
    public static let minimumHitTarget: CGFloat = 44

    /// Padding inside a bar pill.
    public static let pillHorizontalPadding: CGFloat = 14

    /// Corner radius for rectangular chrome surfaces (cards, popovers).
    public static let cardCornerRadius: CGFloat = 18

    /// Outer inset of the chrome from the video edge, tracking the surface
    /// width so an embedded player is not padded like a full-screen one.
    public static func contentInset(for width: CGFloat) -> CGFloat {
        min(max(width * 0.04, spacingM), 32)
    }
}

// MARK: - Motion

/// One motion vocabulary for the whole chrome.
///
/// Hover alone previously came in four flavours (scale 1.02, 1.04, none, and a
/// bespoke shadow ramp), so controls that sit next to each other reacted to the
/// cursor differently.
public enum PlayerChromeMotion {
    public static let hoverScale: CGFloat = 1.06
    public static let pressedScale: CGFloat = 0.94
    public static let hover = Animation.easeOut(duration: 0.16)
    public static let press = Animation.spring(response: 0.22, dampingFraction: 0.72)
    /// Chrome show/hide.
    public static let chrome = Animation.easeInOut(duration: 0.28)
}

// MARK: - Surfaces

/// How much a surface asserts itself.
public enum PlayerSurfaceProminence: Equatable {
    /// A round transport control floating over the video.
    case control
    /// A bar or a group of controls sharing one capsule.
    case bar
    /// The single emphasised action on screen — the skip / next-episode pill.
    /// Takes the host's accent; everything else stays neutral.
    case prominent
}

/// The two shapes chrome surfaces are allowed to take.
///
/// Restricted to a closed set on purpose: `glassEffect`'s shape argument is not
/// a plain `Shape`, so a generic pass-through would either lose the 26+ path or
/// need a shape-erasing wrapper per call site. Two cases cover every control in
/// the player, and the compiler enforces that a third is never invented.
public enum PlayerSurfaceShape: Equatable {
    case circle
    case capsule
}

private struct PlayerGlassSurface: ViewModifier {
    let shape: PlayerSurfaceShape
    let prominence: PlayerSurfaceProminence
    let appearance: PlayerAppearance

    /// Floors the contrast under translucent surfaces.
    ///
    /// Clear glass samples what is behind it, and what is behind the chrome is
    /// arbitrary video. Over a blown-out frame a clear disc leaves white glyphs
    /// on near-white glass — exactly the frame where the control matters. A
    /// constant dark wash under the glass costs one layer and makes every
    /// control legible over any content, without flattening the refraction.
    private var contrastFloor: Color {
        switch prominence {
        case .control, .bar:
            return Color.black.opacity(0.24)
        case .prominent:
            return .clear
        }
    }

    /// The accent as the prominent surface actually wears it.
    ///
    /// A host hands over its brand colour at full strength, and at full
    /// strength `glassEffect`'s tint saturates the material completely: the
    /// skip pill rendered as an opaque neon slab — indistinguishable from a
    /// flat `fill`, which defeats taking the glass path at all. Carrying the
    /// tint at 0.7 is the measured sweet spot (checked over a dark and a
    /// blown-out frame): the brand hue stays unmistakable, the video reads
    /// through the material, the rim light returns, and a black foreground
    /// still clears contrast on both extremes. Lower drifts muddy and off-brand.
    ///
    /// Applied here and not by the host so the finish is a property of the
    /// design layer: every host gets the same glass, and the pre-26 fallback
    /// below still fills with the accent at full strength — an opaque era
    /// should look opaque.
    private var prominentTint: Color {
        appearance.accent.opacity(0.7)
    }

    /// Floor first, then glass, then the glyph.
    ///
    /// The order matters and is easy to get backwards: `content.background(floor)`
    /// followed by `.glassEffect` puts the floor *between* the glass and the
    /// glyph, so the wash dims the material instead of the frame behind it and
    /// the specular highlight is muted. Applying the glass to the content and
    /// the floor behind the result is what `DoubleTapSeekOverlayView`'s
    /// medallion already does, and it is the arrangement the doc comment on
    /// ``contrastFloor`` describes.
    func body(content: Content) -> some View {
        glass(content).background(floorShape)
    }

    @ViewBuilder
    private var floorShape: some View {
        switch shape {
        case .circle:
            Circle().fill(contrastFloor)
        case .capsule:
            Capsule(style: .continuous).fill(contrastFloor)
        }
    }

    @ViewBuilder
    private func glass(_ content: some View) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch (shape, prominence) {
            case (.circle, .prominent):
                content.glassEffect(.regular.tint(prominentTint).interactive(), in: .circle)
            case (.circle, _):
                content.glassEffect(.clear.interactive(), in: .circle)
            case (.capsule, .prominent):
                content.glassEffect(.regular.tint(prominentTint).interactive(), in: .capsule)
            case (.capsule, _):
                content.glassEffect(.clear.interactive(), in: .capsule)
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    /// Pre-26 the same three prominences are built out of material and a hairline.
    ///
    /// The point is that the two eras differ in *finish*, never in size or
    /// position: the fallback keeps the identical shape, padding and stroke
    /// weight so a screenshot taken on macOS 15 and one taken on 26 lay out
    /// pixel-for-pixel.
    @ViewBuilder
    private func fallback(_ content: some View) -> some View {
        switch (shape, prominence) {
        case (.circle, .prominent):
            content
                .background(Circle().fill(appearance.accent))
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        case (.circle, _):
            content
                .thinMaterialBackgroundCompat(in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        case (.capsule, .prominent):
            content
                .background(Capsule(style: .continuous).fill(appearance.accent))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        case (.capsule, _):
            content
                .thinMaterialBackgroundCompat(in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

public extension View {
    /// The chrome's only surface treatment.
    func playerGlass(
        _ shape: PlayerSurfaceShape,
        prominence: PlayerSurfaceProminence = .control,
        appearance: PlayerAppearance = .default
    ) -> some View {
        modifier(
            PlayerGlassSurface(shape: shape, prominence: prominence, appearance: appearance)
        )
    }

    /// Clips and shapes the hit area to the surface, so a corner of the
    /// bounding box is not clickable outside the visible control.
    @ViewBuilder
    func playerSurfaceShape(_ shape: PlayerSurfaceShape) -> some View {
        switch shape {
        case .circle:
            contentShape(Circle()).clipShape(Circle())
        case .capsule:
            contentShape(Capsule(style: .continuous))
                .clipShape(Capsule(style: .continuous))
        }
    }
}

// MARK: - Button behaviour

/// Press and hover feedback for every control in the chrome.
///
/// `buttonStyle(.plain)` was applied to all twenty-odd controls, which removes
/// the system's pressed state and replaced it with nothing: a tap produced no
/// acknowledgement at all until the underlying playback state changed. This
/// keeps `.plain`'s "do not decorate my label" contract and adds back the one
/// thing a button must do.
public struct PlayerControlButtonStyle: ButtonStyle {
    private let hoverEnabled: Bool

    public init(hoverEnabled: Bool = true) {
        self.hoverEnabled = hoverEnabled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PlayerChromeMotion.pressedScale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(PlayerChromeMotion.press, value: configuration.isPressed)
            .desktopHoverLift(enabled: hoverEnabled)
    }
}

public extension View {
    /// Dims a control that is present but cannot act, at one opacity.
    ///
    /// Three different treatments existed — 0.5 on PiP and prev/next, nothing
    /// at all on the ±10 skip buttons, and full removal elsewhere — so "off"
    /// and "unavailable" looked the same in one place and different in another.
    @ViewBuilder
    func playerControlEnabled(_ isEnabled: Bool) -> some View {
        opacity(isEnabled ? 1 : 0.4)
            .animation(PlayerChromeMotion.hover, value: isEnabled)
    }
}

// MARK: - Typography

/// The chrome's type ramp.
///
/// Each role names its own point size — the semantic styles it replaced
/// (`.title2`, `.callout`, `.headline`) put the iPhone timecode at ~17pt, above
/// the player's own title, because they are body-text roles being used for
/// chrome. But the sizes still **scale with Dynamic Type**, anchored to a text
/// style, because freezing them would take the player's only readable text away
/// from anyone who needs it larger. Growth is absorbed by the line limits and
/// `minimumScaleFactor` at the call sites.
public enum PlayerChromeRole {
    case title
    case subtitle
    /// Pills and bar labels.
    case action
    /// Time readouts. Monospaced digits are applied at the call site.
    case timecode
    case badge

    var size: CGFloat {
        switch self {
        case .title: return 19
        case .subtitle: return 13
        case .action: return 14
        case .timecode: return 12
        case .badge: return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .title: return .semibold
        case .subtitle: return .medium
        case .action: return .semibold
        case .timecode: return .medium
        case .badge: return .bold
        }
    }

    /// The style each role scales against, so the ramp keeps its proportions as
    /// the user's text size changes.
    var textStyle: Font.TextStyle {
        switch self {
        case .title: return .title2
        case .subtitle: return .callout
        case .action: return .callout
        case .timecode: return .caption
        case .badge: return .caption2
        }
    }
}

/// Applies a role from the ramp.
///
/// A `ViewModifier` rather than a `Font` constant because `@ScaledMetric` is a
/// property wrapper and needs a view to live in — `Font.system(size:)` alone is
/// a fixed-size font and ignores the user's text-size setting entirely.
private struct PlayerChromeFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(_ role: PlayerChromeRole) {
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.textStyle)
        weight = role.weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

public extension View {
    func playerChromeFont(_ role: PlayerChromeRole) -> some View {
        modifier(PlayerChromeFont(role))
    }
}

public enum PlayerChromeTypography {
    /// Glyph point size for each control tier.
    public static func glyphSize(for diameter: CGFloat) -> CGFloat {
        // Optical ratio held constant across the three tiers, so a 38pt bar
        // icon and a 64pt play glyph look like the same icon set.
        (diameter * 0.42).rounded()
    }
}
