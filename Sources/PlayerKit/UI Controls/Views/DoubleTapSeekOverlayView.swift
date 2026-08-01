import SwiftUI

/// PlayerKit's double-tap skip indicator.
///
/// Three layers, each a single view with no offscreen render pass between them:
///
/// 1. **Edge bloom** — light spilling in from the outer edge of the tapped side,
///    fading to nothing by the midline. There is no panel and no cut-out: the
///    earlier design masked a hard-edged shape over half the picture, which
///    costs an offscreen pass on every animated frame and draws a border across
///    the video that has nothing to do with the video.
/// 2. **Tap ring** — a thin ring opening from the fingertip, sized so it can
///    never reach across the midline (see `tapRingRadius(forWidth:)`), which is
///    what lets it be drawn without any clipping at all.
/// 3. **Readout** — chevrons leading the number in the direction of travel, over
///    a soft radial bloom that carries the white text on bright footage without
///    a blur pass.
///
/// The motion is an impulse rather than a loop: each tap sends the chevrons
/// sweeping outward and pops the number, then everything settles. Nothing
/// animates between taps, so an idle overlay costs nothing to keep on screen.
///
/// Purely presentational — `GestureManager` owns the state.
struct DoubleTapSeekOverlayView: View {
    let state: DoubleTapSeekOverlayState
    let size: CGSize

    /// Springs the readout on each tap. Driven by `tapID` rather than view
    /// identity so the number is not torn down and rebuilt to animate.
    @State private var pop: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isForward: Bool { state.direction == .forward }

    var body: some View {
        ZStack {
            edgeBloom
            tapRing
            readout
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        // Announced from the model instead. A transient element that exists for
        // three quarters of a second steals focus and is gone before the user
        // reaches it.
        .accessibilityHidden(true)
    }

    // MARK: - Layers

    /// Reaches `.clear` exactly at the midline, so the tapped side is shaded and
    /// the other side is untouched without a mask deciding where to stop.
    ///
    /// Deliberately a dark scrim, not a light one. A white wash is invisible on
    /// bright footage — exactly the frames where the overlay most needs to
    /// separate itself from the picture — whereas darkening reads there, and on
    /// already-dark footage there is nothing for it to fight.
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

    @ViewBuilder
    private var tapRing: some View {
        // The expanding ring is pure decoration; Reduce Motion drops it rather
        // than slowing it down, because a slower expanding circle is still an
        // expanding circle.
        if !reduceMotion {
            SeekTapRing(
                center: state.origin(in: size),
                radius: Self.tapRingRadius(forWidth: size.width)
            )
            .id(state.tapID)
        }
    }

    /// A glass medallion, echoing the circular controls the rest of the player
    /// is built from — and echoing the ring that just opened under the finger.
    ///
    /// The glass is what makes the white type readable over any frame, bright or
    /// dark, without a `shadow` blurring the whole readout into an offscreen
    /// buffer on every animated frame.
    private var readout: some View {
        VStack(spacing: 0) {
            SeekChevronsView(isForward: isForward, isAnimated: !reduceMotion)
                .id(state.tapID)
            Text(secondsValue)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigitsCompat()
            Text("SECONDS")
                .font(.system(size: 9, weight: .semibold))
                .trackingCompat(1.8)
                .opacity(0.65)
        }
        .foregroundColor(.white)
        .frame(width: Self.medallionSize, height: Self.medallionSize)
        .modifier(SeekMedallionGlass())
        .scaleEffect(pop)
        .position(x: size.width * (isForward ? 0.75 : 0.25), y: size.height / 2)
        .compatOnChange(of: state.tapID) { _ in
            guard !reduceMotion else { return }
            pop = 1.11
            withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) { pop = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isForward ? "Forward \(secondsValue) seconds" : "Back \(secondsValue) seconds"
        )
    }

    private static let medallionSize: CGFloat = 118

    private var secondsValue: String {
        String(Int(state.seconds.rounded()))
    }

    /// Radius of the tap ring.
    ///
    /// Capped against the width so the ring cannot reach past the midline from
    /// the innermost point a seek tap can land on — the property that lets it be
    /// drawn with no clip. `DoubleTapSeekOverlayGeometryTests` pins it to
    /// `GestureManager`'s zone boundary.
    static func tapRingRadius(forWidth width: CGFloat) -> CGFloat {
        min(90, width * 0.09)
    }
}

// MARK: - Medallion

/// The same glass treatment `circularGlassIcon` gives the player's round
/// buttons, so the skip readout belongs to the same set of controls.
private struct SeekMedallionGlass: ViewModifier {
    func body(content: Content) -> some View {
        glass(content)
            // Tint *under* the glass, which samples it along with the frame
            // behind. Clear glass alone over a blown-out shot leaves white type
            // on a near-white disc; this floors the contrast whatever is
            // playing. `glassBackgroundCompat` tints the same way on macOS.
            .background(Color.black.opacity(0.26), in: Circle())
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.clear, in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
    }
}

// MARK: - Tap ring

/// A ring opening out of the fingertip and dissolving.
private struct SeekTapRing: View {
    let center: CGPoint
    let radius: CGFloat

    @State private var scale: CGFloat = 0.28
    @State private var opacity: Double = 0.85

    var body: some View {
        Circle()
            .strokeBorder(Color.white, lineWidth: 1.5)
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(center)
            .onAppear {
                withAnimation(.easeOut(duration: 0.44)) { scale = 1 }
                withAnimation(.easeIn(duration: 0.32).delay(0.10)) { opacity = 0 }
            }
    }
}

// MARK: - Chevrons

/// Three chevrons sweeping outward in the direction of travel, staggered so the
/// impulse reads as a wave leaving the readout rather than three lights blinking.
private struct SeekChevronsView: View {
    let isForward: Bool
    let isAnimated: Bool

    @State private var swept = false

    private let count = 3

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< count, id: \.self) { index in
                Image(systemName: isForward ? "chevron.right" : "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(isAnimated && swept ? 0.5 : 1)
                    .offset(x: isAnimated && swept ? (isForward ? 7 : -7) : 0)
                    .animation(
                        isAnimated
                            ? .easeOut(duration: 0.5).delay(0.06 * Double(order(of: index)))
                            : nil,
                        value: swept
                    )
            }
        }
        .onAppear { swept = isAnimated }
    }

    /// Forward sweeps left-to-right, backward right-to-left, so the wave always
    /// travels the way the playhead is going.
    private func order(of index: Int) -> Int {
        isForward ? index : (count - 1 - index)
    }
}
