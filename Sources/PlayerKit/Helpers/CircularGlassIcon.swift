//
//  CircularGlassIcon.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 24/09/25.
//

import SwiftUI

// MARK: - Round controls

private struct PlayerControlIcon: ViewModifier {
    let diameter: CGFloat
    let prominence: PlayerSurfaceProminence
    let appearance: PlayerAppearance

    func body(content: Content) -> some View {
        content
            .font(.system(size: PlayerChromeTypography.glyphSize(for: diameter), weight: .semibold))
            .foregroundColor(prominence == .prominent ? appearance.accentForeground : .white)
            .frame(width: diameter, height: diameter)
            .playerSurfaceShape(.circle)
            .playerGlass(.circle, prominence: prominence, appearance: appearance)
            // The 44pt minimum grows the *target*, not the disc, so it has to
            // come after the surface. Applied before it, the flexible frame
            // resolves first and the glass is painted at 44pt — which silently
            // erased the 38pt bar tier, flattening the size ramp to 44/48/64
            // and leaving a 16pt glyph adrift in a 44pt disc.
            .frame(
                minWidth: PlayerChromeMetrics.minimumHitTarget,
                minHeight: PlayerChromeMetrics.minimumHitTarget
            )
            .contentShape(Rectangle())
    }
}

/// A glyph inside a surface that already has one.
///
/// Grouped bars (the media-options pill, the trailing PiP/full-screen pill)
/// used to fill themselves with controls that each carried their own glass
/// disc, stacking glass on glass — which Apple's guidance calls out
/// specifically, and which reads as a smudge rather than as a material.
///
/// The hover response lives *here*, not in a button style, because half of the
/// glyphs in a shared bar are `Menu` triggers: a `ButtonStyle`'s `makeBody` is
/// not applied to a menu label, so styling was how the options pill ended up
/// the one dead spot in the chrome — every disc around it lifted under the
/// cursor while speed/subtitles/audio did nothing. A wash behind the hovered
/// glyph plus the shared lift is also what the system's own player chrome does
/// inside a bar: the surface is shared, the response is per control.
private struct PlayerBarGlyph: ViewModifier {
    let diameter: CGFloat
    let hoverEnabled: Bool

    @State private var isHovering = false

    private var showsHover: Bool { hoverEnabled && isHovering }

    func body(content: Content) -> some View {
        #if os(macOS)
        base(content)
            // The wash is drawn at the glyph's own diameter — inside the bar
            // capsule's 44pt, so the highlight never touches the shared
            // surface's edge — and the lift matches every other control's
            // hover scale.
            .background(
                Circle()
                    .fill(Color.white.opacity(showsHover ? 0.16 : 0))
                    .frame(width: diameter, height: diameter)
            )
            .scaleEffect(showsHover ? PlayerChromeMotion.hoverScale : 1)
            .animation(PlayerChromeMotion.hover, value: showsHover)
            .onHover { hovering in
                isHovering = hovering
            }
        #else
        base(content)
        #endif
    }

    private func base(_ content: Content) -> some View {
        content
            .font(.system(size: PlayerChromeTypography.glyphSize(for: diameter), weight: .semibold))
            .foregroundColor(.white)
            .frame(width: diameter, height: diameter)
            // Sharing a surface is no reason to be harder to hit. Without this
            // the grouped icons were 38pt targets — under the HIG minimum, and
            // down from the 50pt the same buttons had before they were grouped.
            .frame(
                minWidth: PlayerChromeMetrics.minimumHitTarget,
                minHeight: PlayerChromeMetrics.minimumHitTarget
            )
            .contentShape(Rectangle())
    }
}

public extension View {
    /// A round chrome control on its own glass disc.
    func playerControlIcon(
        diameter: CGFloat = PlayerChromeMetrics.barControlDiameter,
        prominence: PlayerSurfaceProminence = .control,
        appearance: PlayerAppearance = .default
    ) -> some View {
        modifier(
            PlayerControlIcon(
                diameter: diameter,
                prominence: prominence,
                appearance: appearance
            )
        )
    }

    /// A glyph that sits inside a shared bar surface and supplies none of its
    /// own — but still answers the cursor on its own, wash plus lift, exactly
    /// because the surface it sits on cannot do that for it.
    func playerBarGlyph(
        diameter: CGFloat = PlayerChromeMetrics.barControlDiameter,
        hoverEnabled: Bool = true
    ) -> some View {
        modifier(PlayerBarGlyph(diameter: diameter, hoverEnabled: hoverEnabled))
    }

    /// - Note: Retained for source compatibility with hosts that styled their
    ///   own controls to match PlayerKit's. Nothing inside the package uses it
    ///   any more. `iconSize` is ignored — the glyph is now derived from the
    ///   control's diameter so the whole set keeps one optical ratio — while
    ///   `desktopHoverEnabled` is still honoured.
    @available(
        *,
        deprecated,
        message: "Use playerControlIcon(diameter:prominence:appearance:). iconSize is ignored; the glyph scales with the control."
    )
    func circularGlassIcon(
        iconSize: CGFloat = 20,
        frameSize: CGFloat = 30,
        padding: CGFloat = 10,
        desktopHoverEnabled: Bool = true
    ) -> some View {
        playerControlIcon(diameter: frameSize + (padding * 2))
            .desktopHoverLift(enabled: desktopHoverEnabled)
    }
}
