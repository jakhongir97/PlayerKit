import SwiftUI

/// PlayerKit's double-tap skip indicator, drawn with YouTube's anatomy.
///
/// The double tap *is* YouTube's gesture, so the feedback borrows YouTube's
/// visual language wholesale — the shape every viewer already knows how to
/// read. An earlier design drew a scaled-up twin of the ±10 transport button
/// with the running total *inside* the glyph; a 56pt disc leaves ~24pt for the
/// number, so "30" was cramped and "110" shrank into illegibility. Here the
/// total is a full-size text line and nothing has to fit inside anything.
///
/// Four layers, back to front:
///
/// 1. **Edge bloom** — dark light-falloff from the tapped edge, reaching
///    `.clear` at the midline. Deliberately dark, not light: a white wash is
///    invisible on bright footage — exactly the frames where the overlay most
///    needs to separate itself — whereas darkening reads there, and on
///    already-dark footage there is nothing for it to fight. It doubles as the
///    contrast floor for the white cluster above it.
/// 2. **Sector wash** — YouTube's signature shape: a translucent sheet over
///    the tapped half whose inner edge is a circular arc bulging toward the
///    midline. A circle anchored at the outer edge, clipped to the tapped
///    half, so it cannot reach the other side by construction.
/// 3. **Tap ripple** — a soft filled circle expanding from the fingertip on
///    every tap, clipped with the wash. Anchoring at the finger is safe here
///    because the clip owns containment; the old ring needed geometry to
///    promise it stayed in its half.
/// 4. **The cluster** — three chevrons pointing the way the seek is going,
///    animated as a sequential wave, with "N SECONDS" beneath them. The wave
///    runs while the session is up; each further tap pops the cluster and
///    replays the ripple from the new fingertip.
///
/// Reduce Motion drops the ripple and freezes the wave at its staggered
/// resting opacities — the direction still reads, nothing loops.
///
/// Purely presentational — `GestureManager` owns the state.
struct DoubleTapSeekOverlayView: View {
    let state: DoubleTapSeekOverlayState
    let size: CGSize
    let strings: PlayerStrings

    /// Impulses driven by `tapID` rather than view identity, so the cluster is
    /// not torn down and rebuilt to animate.
    @State private var pop: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isForward: Bool { state.direction == .forward }

    var body: some View {
        ZStack {
            edgeBloom
            sectorWash
            cluster
        }
        .frame(width: size.width, height: size.height)
        // This overlay is pure physical geometry: the tap zones it echoes are
        // raw touch coordinates (`GestureGeometry.tapZone` deliberately does
        // not RTL-convert the left/right halves), so the drawing must not
        // mirror either. Without this pin, right-to-left layout mirrors the
        // whole overlay — wash, bloom, cluster — onto the *untapped* half
        // while the machine keeps seeking for the half the finger is on.
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        // Announced from the model instead. A transient element that exists for
        // three quarters of a second steals focus and is gone before the user
        // reaches it.
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    /// Reaches `.clear` exactly at the midline, so the tapped side is shaded and
    /// the other side is untouched without a mask deciding where to stop.
    private var edgeBloom: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .black.opacity(0.34), location: 0.00),
                .init(color: .black.opacity(0.16), location: 0.18),
                .init(color: .black.opacity(0.04), location: 0.36),
                .init(color: .clear, location: 0.50)
            ]),
            startPoint: isForward ? .trailing : .leading,
            endPoint: isForward ? .leading : .trailing
        )
    }

    /// The arc-edged sheet plus the per-tap ripple, both living inside a
    /// clipped half-width container so neither can cross the midline no matter
    /// what the surface's aspect ratio does to the circle.
    private var sectorWash: some View {
        let halfWidth = size.width / 2
        let washRadius = Self.washRadius(for: size)
        // The wash circle is anchored at the outer edge of the tapped half, in
        // the half-container's own coordinates.
        let anchorX: CGFloat = isForward ? halfWidth : 0

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.09))
                .frame(width: washRadius * 2, height: washRadius * 2)
                .position(x: anchorX, y: size.height / 2)

            // The ripple is pure decoration; Reduce Motion drops it rather
            // than slowing it down, because a slower expanding circle is still
            // an expanding circle.
            if !reduceMotion {
                SeekTapRipple(
                    center: rippleCenter(halfWidth: halfWidth),
                    maxRadius: Self.pulseReach(forWidth: size.width) * 3
                )
                .id(state.tapID)
            }
        }
        .frame(width: halfWidth, height: size.height)
        .clipped()
        // Placed with `.position`, never an alignment frame: `.leading` and
        // `.trailing` flip under right-to-left layout, while the tap zones,
        // the cluster and the bloom are all physical-x — an aligned container
        // would put the wash on the untapped half for RTL hosts. The centre of
        // the tapped half is exactly `pulseCenterX`.
        .position(
            x: Self.pulseCenterX(forWidth: size.width, isForward: isForward),
            y: size.height / 2
        )
    }

    /// The fingertip, translated into the half-container's coordinates.
    private func rippleCenter(halfWidth: CGFloat) -> CGPoint {
        let surfaceX = state.unitOrigin.x * size.width
        return CGPoint(
            x: isForward ? surfaceX - halfWidth : surfaceX,
            y: state.unitOrigin.y * size.height
        )
    }

    /// Chevrons above, total below — YouTube's arrangement, centred in the
    /// tapped side zone on the transport's own line.
    private var cluster: some View {
        VStack(spacing: 10) {
            SeekChevronWave(isForward: isForward, animated: !reduceMotion)
            Text(secondsLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .kerning(0.8)
                .monospacedDigitsCompat()
                .lineLimit(1)
        }
        .foregroundColor(.white)
        // The cluster sits on footage, not on glass; the shadow is its
        // contrast floor for the frames the edge bloom cannot darken enough.
        .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
        .scaleEffect(pop)
        .position(
            x: Self.pulseCenterX(forWidth: size.width, isForward: isForward),
            y: size.height / 2
        )
        .compatOnChange(of: state.tapID) { _ in
            guard !reduceMotion else { return }
            // The jump to 1.07 must not animate, and on iOS 17/macOS 14 this
            // closure runs inside the tap's own transaction — where the host's
            // `.animation(_, value: seekOverlay)` has planted a 0.18s ease that
            // would stretch the jump across it and flatten the pop entirely.
            var impulse = Transaction()
            impulse.disablesAnimations = true
            withTransaction(impulse) { pop = 1.07 }
            withAnimation(PlayerChromeMotion.press) { pop = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isForward ? strings.forwardSeconds(state.seconds) : strings.backSeconds(state.seconds)
        )
    }

    private var secondsLabel: String {
        "\(Int(state.seconds.rounded())) \(strings.seconds)"
    }

    /// Nominal diameter of the cluster's core content. The ripple's reach is
    /// held above half of this by test, so the ripple always visibly escapes
    /// the cluster instead of dying underneath it.
    static let discDiameter: CGFloat = 56

    // MARK: - Geometry contract

    /// The cluster's centre: the middle of each side zone.
    ///
    /// `DoubleTapSeekGestureTests` holds `pulseCenterX ± pulseReach` inside the
    /// tapped half, so even the unclipped layer — the cluster — stays where a
    /// tap on the other side could never have put it.
    static func pulseCenterX(forWidth width: CGFloat, isForward: Bool) -> CGFloat {
        width * (isForward ? 0.75 : 0.25)
    }

    /// The ripple's base radius (the drawn ripple reaches three of these
    /// before the clip). Capped against the width so the *contract* radius can
    /// never reach the midline from a centre pinned at quarter-width; the
    /// width term only bites below a 250pt surface.
    static func pulseReach(forWidth width: CGFloat) -> CGFloat {
        min(60, width * 0.24)
    }

    /// The wash circle's radius: far enough in for the arc to read as
    /// YouTube's lens, tall enough to span the surface near the tapped edge.
    /// On tall surfaces the height term wins and the clip turns the wash into
    /// a plain half-sheet — the degenerate case YouTube shows there too.
    static func washRadius(for size: CGSize) -> CGFloat {
        max(size.width * 0.42, size.height * 0.6)
    }
}

// MARK: - Chevron wave

/// YouTube's triple chevron, running its sequential opacity wave.
///
/// The three triangles rest at staggered opacities so a single static frame
/// already reads as motion in the seek's direction; the loop then carries each
/// one between its floor and full strength, offset by its position. Backward
/// mirrors the whole row, which flips both the triangles and the direction the
/// wave travels.
private struct SeekChevronWave: View {
    let isForward: Bool
    let animated: Bool

    @State private var isWaving = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 3, id: \.self) { index in
                Image(systemName: "play.fill")
                    .font(.system(size: 19, weight: .bold))
                    .opacity(opacity(for: index))
                    .animation(waveAnimation(for: index), value: isWaving)
            }
        }
        .scaleEffect(x: isForward ? 1 : -1, y: 1)
        .onAppear {
            guard animated else { return }
            isWaving = true
        }
    }

    /// Resting opacities lead from the direction of travel — a static frame
    /// still reads as motion. The wave then carries each chevron between its
    /// own floor and full strength (the floors must sit below 1, or the
    /// leading chevron's loop would animate 1 → 1 and never move).
    private func opacity(for index: Int) -> Double {
        guard animated else { return [1.0, 0.7, 0.45][index] }
        return isWaving ? 1 : [0.55, 0.4, 0.25][index]
    }

    private func waveAnimation(for index: Int) -> Animation? {
        guard animated else { return nil }
        return .easeInOut(duration: 0.4)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.13)
    }
}

// MARK: - Tap ripple

/// A soft filled circle expanding from the fingertip and dissolving — the
/// second half of YouTube's tap feedback. Containment is the clip's job, so
/// the ripple is free to grow from wherever the finger actually landed.
private struct SeekTapRipple: View {
    let center: CGPoint
    let maxRadius: CGFloat

    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.26),
                        Color.white.opacity(0.10),
                        Color.white.opacity(0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: maxRadius
                )
            )
            .frame(width: maxRadius * 2, height: maxRadius * 2)
            .scaleEffect(expanded ? 1 : 0.35)
            .opacity(expanded ? 0 : 0.9)
            .position(center)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { expanded = true }
            }
    }
}
